#!/usr/bin/env python3
import argparse
import json
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path('/Users/avrohom/Downloads/journeyatlas')
DEFAULT_OUT = ROOT / 'atlas-concierge/kb/training/scientific_papers_openalex.jsonl'
DEFAULT_QUERY_FILE = ROOT / 'atlas-concierge/kb/training/openalex_atlas_queries.txt'

DEFAULT_QUERIES = [
    'goal setting performance',
    'implementation intentions behavior change',
    'habit formation self regulation',
    'sleep deprivation executive function',
    'stress decision making',
    'resilience trauma recovery',
    'financial behavior savings automation',
    'transport safety fatigue driving',
    'mobility wellbeing',
    'time management productivity',
]


def inverted_index_to_text(inv):
    if not isinstance(inv, dict):
        return ''
    positions = []
    for token, indexes in inv.items():
        if not isinstance(indexes, list):
            continue
        for idx in indexes:
            if isinstance(idx, int):
                positions.append((idx, token))
    positions.sort(key=lambda x: x[0])
    return ' '.join(token for _, token in positions)


def domain_from_query(query: str) -> str:
    q = query.lower()
    if any(k in q for k in ['financial', 'savings', 'revenue', 'wealth']):
        return 'wealth'
    if any(k in q for k in ['transport', 'mobility', 'driving', 'travel']):
        return 'travel'
    if any(k in q for k in ['stress', 'resilience', 'trauma', 'safety']):
        return 'resilience'
    if any(k in q for k in ['sleep', 'recovery', 'wellbeing', 'health']):
        return 'recovery'
    if any(k in q for k in ['time management', 'productivity', 'habit', 'goal', 'implementation']):
        return 'execution'
    return 'planning'


def fetch_json(url: str):
    req = urllib.request.Request(url, headers={'User-Agent': 'atlas-corpus-builder/1.0'})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode('utf-8'))


def read_query_file(path: Path):
    queries = []
    if not path.exists():
        return queries
    for raw in path.read_text(encoding='utf-8').splitlines():
        line = raw.strip()
        if not line or line.startswith('#'):
            continue
        queries.append(line)
    return queries


def best_source_url(work):
    doi = str(work.get('doi') or '').strip()
    if doi.startswith('https://doi.org/'):
        return doi
    if doi:
        return f'https://doi.org/{doi}'

    primary = work.get('primary_location') or {}
    source = primary.get('source') or {}
    host = str(source.get('host_organization_name') or '').strip()
    if host:
        return str(work.get('id') or '')
    return str(work.get('id') or '')


def build_actionable_insight(abstract: str, domain: str):
    if not abstract:
        return f'Research in {domain} indicates measurable behavior and performance effects under real constraints.'
    parts = [p.strip() for p in abstract.split('. ') if p.strip()]
    joined = '. '.join(parts[:2]).strip()
    if len(joined) < 30:
        return f'Research in {domain} indicates measurable behavior and performance effects under real constraints.'
    if len(joined) > 320:
        return joined[:317].rstrip() + '...'
    return joined


def main():
    parser = argparse.ArgumentParser(description='Fetch Atlas-relevant scientific papers from OpenAlex into JSONL corpus format.')
    parser.add_argument('--query', action='append', default=[], help='Search query. Repeat for multiple domains.')
    parser.add_argument('--query-file', default=str(DEFAULT_QUERY_FILE), help='Optional newline-delimited query file')
    parser.add_argument('--pages', type=int, default=5, help='Pages per query')
    parser.add_argument('--per-page', type=int, default=100, help='Items per page (max depends on OpenAlex limits)')
    parser.add_argument('--from-year', type=int, default=1990, help='Lower bound publication year')
    parser.add_argument('--max-papers', type=int, default=25000, help='Hard cap on total papers')
    parser.add_argument('--mailto', default='', help='Contact email for polite pool')
    parser.add_argument('--output', default=str(DEFAULT_OUT), help='Output JSONL path')
    parser.add_argument('--sleep-ms', type=int, default=200, help='Delay between requests')
    parser.add_argument('--verbose', action='store_true')
    args = parser.parse_args()

    queries = []
    if args.query:
        queries.extend(args.query)
    query_file = Path(args.query_file).expanduser().resolve()
    queries.extend(read_query_file(query_file))
    if not queries:
        queries = list(DEFAULT_QUERIES)
    queries = [q.strip() for q in queries if q.strip()]
    # keep order but dedupe
    seen = set()
    deduped_queries = []
    for q in queries:
        low = q.lower()
        if low in seen:
            continue
        seen.add(low)
        deduped_queries.append(q)
    queries = deduped_queries

    output = Path(args.output).expanduser().resolve()
    output.parent.mkdir(parents=True, exist_ok=True)

    dedup = {}
    for query in queries:
        domain = domain_from_query(query)
        for page in range(1, max(1, args.pages) + 1):
            params = {
                'search': query,
                'filter': f'has_abstract:true,type:article,from_publication_date:{args.from_year}-01-01',
                'per-page': str(args.per_page),
                'page': str(page),
            }
            if args.mailto:
                params['mailto'] = args.mailto
            url = 'https://api.openalex.org/works?' + urllib.parse.urlencode(params)
            try:
                payload = fetch_json(url)
            except Exception as exc:
                print(f'warn query={query!r} page={page}: {exc}')
                continue

            results = payload.get('results', [])
            if not results:
                break

            if args.verbose:
                print(f'query={query!r} page={page} results={len(results)}')

            for work in results:
                wid = str(work.get('id') or '').strip()
                title = str(work.get('display_name') or '').strip()
                year = int(work.get('publication_year') or 0)
                if not wid or not title or year < args.from_year:
                    continue

                abstract = inverted_index_to_text(work.get('abstract_inverted_index'))
                if not abstract:
                    continue

                keywords = []
                for concept in (work.get('concepts') or [])[:8]:
                    name = str(concept.get('display_name') or '').strip().lower()
                    if name:
                        keywords.append(name)

                source_url = best_source_url(work)
                actionable_insight = build_actionable_insight(abstract, domain)

                action_hint = f'Apply one {domain} action today and verify outcome with a checkpoint.'

                row = {
                    'id': wid.rsplit('/', 1)[-1].lower(),
                    'title': title,
                    'year': year,
                    'domain': domain,
                    'actionable_insight': actionable_insight,
                    'action_hint': action_hint,
                    'source_url': source_url,
                    'keywords': sorted(set(keywords))[:12],
                }
                dedup[(title.lower(), year)] = row
                if len(dedup) >= args.max_papers:
                    break

            if len(dedup) >= args.max_papers:
                break

            time.sleep(max(0, args.sleep_ms) / 1000.0)
        if len(dedup) >= args.max_papers:
            break

    rows = sorted(dedup.values(), key=lambda r: (-r['year'], r['title']))
    with output.open('w', encoding='utf-8') as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False) + '\n')

    print(f'queries={len(queries)}')
    print(f'papers={len(rows)}')
    print(f'query_file={query_file}')
    print(f'output={output}')


if __name__ == '__main__':
    main()
