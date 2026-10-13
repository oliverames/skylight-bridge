#!/usr/bin/env python3
"""Validate Skylight documentation from Git objects without application services."""
import hashlib
import html
import json
import os
import posixpath
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote, urlsplit

BOOTSTRAP_BASE = 'edb1ff154c83fb5b8136415a6f944172e07b5d12'
BOOTSTRAP_WORKFLOW_BLOB = 'a28457007a20b2617aadaf2824045302991eb861'
WORKFLOW = '.github/workflows/ci.yml'
CHECKER = 'script/validate_documentation.py'
ARCHIVE = re.compile(r'WORKLOG-(\d{4}-\d{2}-\d{2})\.md\Z')
MANIFEST = re.compile(r'docs/archive/worklog-(\d{4}-\d{2}-\d{2})\.json\Z')
SHA = re.compile(r'[0-9a-f]{40}\Z')
DATE = re.compile(r'\b(?:20\d\d-\d\d-\d\d|January|February|March|April|May|June|July|August|September|October|November|December)\b', re.I)


def require(ok, message):
    if not ok:
        raise ValueError(message)


class Repo:
    def __init__(self, path='.'):
        self.path = path

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.path), *args], stderr=subprocess.PIPE)

    def commit(self, value):
        require(bool(SHA.fullmatch(value or '')) and value != '0' * 40, 'Missing or invalid comparison commit')
        require(self.git('rev-parse', '--verify', value + '^{commit}').decode().strip() == value, 'Unresolved comparison commit')
        return value

    def tree(self, revision):
        result = {}
        for record in self.git('ls-tree', '-r', '-z', revision).split(b'\0'):
            if not record:
                continue
            metadata, path = record.split(b'\t', 1)
            mode, kind, oid = metadata.decode('ascii').split()
            result[path.decode('utf-8')] = (mode, kind, oid)
        return result

    def blob(self, tree, path):
        require(path in tree and tree[path][:2] == ('100644', 'blob'), 'Expected ordinary tracked file: ' + path)
        return self.git('cat-file', 'blob', tree[path][2])

    def ancestor(self, older, newer):
        return subprocess.run(['git', '-C', str(self.path), 'merge-base', '--is-ancestor', older, newer], capture_output=True).returncode == 0


def doc_path(path):
    return path in {'README.md', 'WORKLOG.md'} or bool(ARCHIVE.fullmatch(path) or MANIFEST.fullmatch(path))


def proposed_workflow(original):
    checkout = '      - uses: actions/checkout@v7\n'
    require(original.count(checkout) == 1, 'Unexpected bootstrap checkout structure')
    replacement = '''      - uses: actions/checkout@v7
        with:
          fetch-depth: 0

      - name: Classify changes
        id: changes
        env:
          EVENT_NAME: ${{ github.event_name }}
          BASE_SHA: ${{ github.event.pull_request.base.sha || github.event.before }}
          HEAD_SHA: ${{ github.sha }}
        run: python3 script/validate_documentation.py classify

      - name: Validate documentation
        if: success() && steps.changes.outputs.docs_only == 'true'
        env:
          EVENT_NAME: ${{ github.event_name }}
          BASE_SHA: ${{ github.event.pull_request.base.sha || github.event.before }}
          HEAD_SHA: ${{ github.sha }}
        run: python3 script/validate_documentation.py validate
'''
    result = original.replace(checkout, replacement)
    for name in ['Configure private package access', 'Build', 'Test']:
        old = '      - name: ' + name + '\n'
        require(result.count(old) == 1, 'Unexpected bootstrap native step: ' + name)
        result = result.replace(old, old + "        if: success() && steps.changes.outputs.docs_only != 'true'\n")
    return result


def classify(repo, event, base, head):
    if event == 'workflow_dispatch':
        return False, 'Manual run retains the native path'
    require(event in {'pull_request', 'push'}, 'Unknown workflow event')
    base, head = repo.commit(base), repo.commit(head)
    require(repo.ancestor(base, head), 'Comparison base is not an ancestor of checked-out head')
    before, after = repo.tree(base), repo.tree(head)
    changed = {p for p in before.keys() | after.keys() if before.get(p) != after.get(p)}
    require(changed, 'Empty comparison cannot establish documentation validation')
    for path in changed:
        for tree in [before, after]:
            if path in tree and tree[path][:2] != ('100644', 'blob'):
                return False, 'Non-regular or executable change: ' + path
    ci_changes = changed & {WORKFLOW, CHECKER}
    bootstrap = base == BOOTSTRAP_BASE and ci_changes == {WORKFLOW, CHECKER}
    if bootstrap:
        require(before.get(WORKFLOW, ('', '', ''))[2] == BOOTSTRAP_WORKFLOW_BLOB, 'Unexpected bootstrap workflow baseline')
        require(CHECKER not in before and CHECKER in after, 'Bootstrap checker must be newly added')
        original = repo.blob(before, WORKFLOW).decode()
        require(repo.blob(after, WORKFLOW).decode() == proposed_workflow(original), 'Bootstrap workflow differs from reviewed transformation')
    permitted = {WORKFLOW, CHECKER} if bootstrap else set()
    excluded = sorted(p for p in changed if not doc_path(p) and p not in permitted)
    if excluded:
        return False, 'Native input changed: ' + ', '.join(excluded)
    require(any(doc_path(p) for p in changed), 'No documentation changed')
    return True, 'Reviewed bootstrap plus documentation' if bootstrap else 'Curated documentation only'


def headings(markdown):
    rows, counts, fence = [], {}, None
    for line in markdown.splitlines():
        opening = re.match(r'^\s*(`{3,}|~{3,})', line)
        if opening:
            marker = opening.group(1)[0]
            fence = None if fence == marker else marker if fence is None else fence
            continue
        if fence:
            continue
        match = re.match(r'^(#{1,6})[ \t]+(.+?)(?:[ \t]+#+)?[ \t]*$', line)
        if not match:
            continue
        label = html.unescape(re.sub(r'<[^>]*>', '', match.group(2))).lower()
        label = re.sub(r'\[([^]]+)\]\([^)]*\)', r'\1', label).replace('`', '')
        slug = re.sub(r'[^\w\- ]', '', label).replace(' ', '-')
        count = counts.get(slug, 0)
        counts[slug] = count + 1
        rows.append(slug if not count else slug + '-' + str(count))
    return rows


def anchors(markdown):
    return set(headings(markdown)) | set(re.findall(r'<a\s+(?:id|name)=["\']([^"\']+)["\']', markdown))


def links(markdown):
    # Current guides use inline Markdown links, including <paths with spaces>.
    result = [a or b for a, b in re.findall(r'\]\((?:<([^>]+)>|([^\s)]+))(?:\s+["\'][^)]*["\'])?\)', markdown)]
    result += [a or b for a, b in re.findall(r'^ {0,3}\[[^]]+\]:\s*(?:<([^>]+)>|(\S+))', markdown, re.M)]
    result += re.findall(r'(?:href|src)=["\']([^"\']+)["\']', markdown)
    return result


def validate_links(repo, tree, document, targets):
    checked = 0
    for target in targets:
        split = urlsplit(target)
        if split.scheme or split.netloc:
            continue
        raw_path = unquote(split.path)
        path = posixpath.normpath(posixpath.join(posixpath.dirname(document), raw_path)) if raw_path else document
        require(not path.startswith('../') and not path.startswith('/'), 'Link escapes repository: ' + target)
        require(path in tree or any(p.startswith(path.rstrip('/') + '/') for p in tree), 'Missing local link: ' + document + ' -> ' + target)
        if path in tree:
            require(tree[path][1] == 'blob' and tree[path][0] in {'100644', '100755'}, 'Link target is not a regular Git file: ' + target)
        if split.fragment and path.lower().endswith('.md'):
            body = repo.blob(tree, path).decode()
            require(unquote(split.fragment) in anchors(body), 'Missing heading: ' + document + ' -> ' + target)
        checked += 1
    return checked


def dated_sections(markdown):
    lines = markdown.splitlines(keepends=True)
    positions = [(i, len(m.group(1)), m.group(2)) for i, line in enumerate(lines)
                 if (m := re.match(r'^(#{1,6})\s+(.+?)\s*$', line))]
    result = []
    for i, level, label in positions:
        if not DATE.search(label):
            continue
        end = next((j for j, other_level, _ in positions if j > i and other_level <= level), len(lines))
        result.append(''.join(lines[i:end]).strip())
    return result


def validate(repo, event, base, head):
    is_docs, reason = classify(repo, event, base, head)
    require(is_docs, 'Documentation validator requires the classified docs path: ' + reason)
    before, after = repo.tree(base), repo.tree(head)
    changed = {p for p in before.keys() | after.keys() if before.get(p) != after.get(p)}
    for path, entry in before.items():
        if ARCHIVE.fullmatch(path) or MANIFEST.fullmatch(path):
            require(after.get(path) == entry, 'Existing historical record must remain byte-for-byte unchanged: ' + path)
    archive_paths = {p for p in after if ARCHIVE.fullmatch(p)}
    manifest_paths = {p for p in after if MANIFEST.fullmatch(p)}
    require(archive_paths, 'No preserved worklog archive')
    require({ARCHIVE.fullmatch(p).group(1) for p in archive_paths} == {MANIFEST.fullmatch(p).group(1) for p in manifest_paths}, 'Orphaned archive or manifest')
    require('WORKLOG.md' in after, 'Current worklog is missing')
    current = repo.blob(after, 'WORKLOG.md').decode()
    current_ids, current_links = anchors(current), set(links(current))
    archived_bodies = []
    heading_count = 0
    for path in sorted(manifest_paths):
        record = json.loads(repo.blob(after, path))
        date = MANIFEST.fullmatch(path).group(1)
        archive_path = 'WORKLOG-' + date + '.md'
        require(record['source_path'] == 'WORKLOG.md' and record['archive_path'] == archive_path, 'Manifest path mismatch: ' + path)
        revision = repo.commit(record['source_revision'])
        require(repo.ancestor(revision, head), 'Archive source is not an ancestor: ' + path)
        source_tree = repo.tree(revision)
        source = repo.blob(source_tree, 'WORKLOG.md')
        archived = repo.blob(after, archive_path)
        require(archived == source, 'Archive differs from source bytes: ' + archive_path)
        require(len(archived) == record['bytes'], 'Archive byte count mismatch')
        require(hashlib.sha256(archived).hexdigest() == record['sha256'], 'Archive SHA-256 mismatch')
        require(source_tree['WORKLOG.md'][2] == record['git_blob'], 'Archive Git blob mismatch')
        original = source.decode()
        archived_bodies.append(original)
        expected = headings(original)
        require(record['forwarded_anchors'] == expected, 'Manifest does not enumerate original heading IDs')
        for anchor in expected:
            require(anchor in current_ids, 'Original worklog heading no longer addressable: ' + anchor)
            require(archive_path + '#' + anchor in current_links, 'Original heading lacks archive link: ' + anchor)
        heading_count += len(expected)
        correction = record.get('readme_correction')
        if correction:
            original_readme = repo.blob(source_tree, 'README.md').decode()
            require(source_tree['README.md'][2] == correction['source_git_blob'], 'README source blob mismatch')
            old, replacement = correction['original_paragraph'], correction['replacement_paragraph']
            require(original_readme.count(old) == 1 and bool(replacement), 'Invalid README source snapshot')
            # Historical snapshots remain valid after later README edits.
            if path in changed:
                current_readme = repo.blob(after, 'README.md').decode()
                require(current_readme.count(replacement) == 1, 'New README correction is missing')
                require(current_readme.replace(replacement, old, 1) == original_readme, 'New README correction does not reconstruct its source')
    old_worklog = repo.blob(before, 'WORKLOG.md').decode()
    if 'WORKLOG.md' in changed:
        newly_added_archives = archive_paths - before.keys()
        if newly_added_archives:
            require(any(repo.blob(after, p) == repo.blob(before, 'WORKLOG.md') for p in newly_added_archives), 'New compaction must preserve the complete prior worklog')
        for section in dated_sections(old_worklog):
            require(section in current or any(section in body for body in archived_bodies), 'Prior dated worklog entry was removed without preservation')
    checked_links = validate_links(repo, after, 'WORKLOG.md', links(current))
    if 'README.md' in changed:
        previous_links = set(links(repo.blob(before, 'README.md').decode())) if 'README.md' in before else set()
        changed_links = set(links(repo.blob(after, 'README.md').decode())) - previous_links
        checked_links += validate_links(repo, after, 'README.md', changed_links)
    # Exact archives can contain old whitespace; inspect only changed current lines.
    current_paths = [p for p in changed if p in after and not ARCHIVE.fullmatch(p)]
    repo.git('diff', '--check', base, head, '--', *sorted(current_paths))
    return {'archives': len(archive_paths), 'preserved_heading_ids': heading_count, 'local_links_checked': checked_links, 'classification': reason}


def main():
    require(len(sys.argv) == 2 and sys.argv[1] in {'classify', 'validate'}, 'Expected classify or validate')
    repo = Repo()
    event, base, head = (os.environ.get(name, '') for name in ['EVENT_NAME', 'BASE_SHA', 'HEAD_SHA'])
    if sys.argv[1] == 'classify':
        result, reason = classify(repo, event, base, head)
        output = os.environ.get('GITHUB_OUTPUT')
        require(bool(output), 'Missing GitHub output file')
        with open(output, 'a', encoding='utf-8') as stream:
            stream.write('docs_only=' + str(result).lower() + '\n')
        print(reason)
    else:
        print(json.dumps(validate(repo, event, base, head), sort_keys=True))


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, TypeError, UnicodeError, json.JSONDecodeError, subprocess.CalledProcessError) as error:
        print('Documentation check failed: ' + str(error), file=sys.stderr)
        sys.exit(1)
