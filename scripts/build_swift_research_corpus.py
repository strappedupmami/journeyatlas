#!/usr/bin/env python3
import argparse
import datetime as dt
import json
from collections import Counter
from pathlib import Path
from typing import Dict, List

ROOT = Path('/Users/avrohom/Downloads/journeyatlas')

DEFAULT_INPUT = ROOT / 'atlas-concierge/kb/training/scientific_papers_seed.jsonl'
IOS_PACK = ROOT / 'ios-app/AtlasMasaIOS/Sources/Core/AtlasResearchPack.swift'
MAC_PACK = ROOT / 'macos-app/AtlasMasaMacOS/Sources/Core/AtlasResearchPack.swift'
SCI_TRAINING = ROOT / 'atlas-concierge/kb/training/local_reasoner_training_science.jsonl'
BASE_TRAINING = ROOT / 'atlas-concierge/kb/training/local_reasoner_training.jsonl'
REPORT = ROOT / 'docs/ai/swift-scientific-corpus-report.md'

LABEL_MAP = {
    'wealth': 'travel_design_revenue',
    'travel': 'travel_design_journey_ops',
    'mobility': 'travel_design_journey_ops',
    'operations': 'travel_design_journey_ops',
    'novelty': 'travel_design_journey_ops',
    'exploration': 'travel_design_journey_ops',
    'reflection': 'travel_design_strategy',
    'safety': 'travel_design_resilience',
    'resilience': 'travel_design_resilience',
    'recovery': 'travel_design_recovery',
    'health': 'travel_design_recovery',
    'wellbeing': 'travel_design_recovery',
    'neuroplasticity': 'travel_design_recovery',
    'cognitive-aging': 'travel_design_recovery',
    'brain-health': 'travel_design_recovery',
    'cognitive-reserve': 'travel_design_recovery',
    'execution': 'travel_design_execution',
    'productivity': 'travel_design_execution',
    'planning': 'travel_design_strategy',
    'decision-quality': 'travel_design_strategy',
    'motivation': 'travel_design_strategy',
    'skill-building': 'travel_design_strategy',
    'team-ops': 'travel_design_strategy',
    'emergency-response': 'travel_design_emergency_command',
    'emergency-preparedness': 'travel_design_emergency_command',
    'emergency-management': 'travel_design_emergency_command',
    'crisis-management': 'travel_design_emergency_command',
    'crisis-planning': 'travel_design_emergency_command',
    'incident-command': 'travel_design_emergency_command',
    'human-problem-solving': 'travel_design_human_problem_solving',
    'human-performance': 'travel_design_human_problem_solving',
    'biological-performance': 'travel_design_human_problem_solving',
    'environmental-performance': 'travel_design_human_problem_solving',
    'problem-solving': 'travel_design_human_problem_solving',
    'technology-innovation': 'travel_design_tech_innovation',
    'systems-innovation': 'travel_design_tech_innovation',
    'digital-innovation': 'travel_design_tech_innovation',
    'physical-innovation': 'travel_design_tech_innovation',
    'innovation': 'travel_design_tech_innovation',
}


def _normalize_keywords(value):
    if isinstance(value, list):
        return [str(x).strip().lower() for x in value if str(x).strip()]
    if isinstance(value, str):
        parts = [p.strip().lower() for p in value.replace(';', ',').split(',')]
        return [p for p in parts if p]
    return []


def load_jsonl(paths: List[Path]) -> List[Dict]:
    rows = []
    for path in paths:
        if not path.exists():
            raise FileNotFoundError(f'missing input corpus file: {path}')
        normalized_text = path.read_text(encoding='utf-8').replace('\\n', '\n')
        for raw in normalized_text.splitlines():
            line = raw.strip()
            if not line:
                continue
            row = json.loads(line)
            title = str(row.get('title', '')).strip()
            year = int(row.get('year', 0) or 0)
            if not title or year <= 0:
                continue

            normalized = {
                'id': str(row.get('id') or f"paper-{abs(hash(title + str(year))) % 1_000_000}").strip(),
                'title': title,
                'year': year,
                'domain': str(row.get('domain') or 'execution').strip().lower(),
                'actionable_insight': str(row.get('actionable_insight') or '').strip(),
                'action_hint': str(row.get('action_hint') or '').strip(),
                'source_url': str(row.get('source_url') or row.get('doi') or '').strip(),
                'keywords': _normalize_keywords(row.get('keywords', [])),
            }

            if not normalized['actionable_insight']:
                normalized['actionable_insight'] = 'Evidence suggests structured execution improves outcomes under constraints.'
            if not normalized['action_hint']:
                normalized['action_hint'] = 'Define one concrete next step and execute within the next focused block.'
            if not normalized['source_url']:
                normalized['source_url'] = 'https://doi.org/'
            if not normalized['keywords']:
                normalized['keywords'] = [normalized['domain'], 'execution', 'atlas']
            rows.append(normalized)

    dedup = {}
    for row in rows:
        key = (row['title'].lower(), row['year'])
        dedup[key] = row
    return sorted(dedup.values(), key=lambda r: (-r['year'], r['title']))


def to_swift_pack(rows: List[Dict], output: Path):
    payload = json.dumps(rows, ensure_ascii=False, indent=2)
    content = f'''import Foundation

enum AtlasResearchPack {{
    static func load() -> [AtlasResearchPaper] {{
        guard let data = atlasResearchPackJSON.data(using: .utf8) else {{
            return []
        }}
        return (try? JSONDecoder().decode([AtlasResearchPaper].self, from: data)) ?? []
    }}
}}

private let atlasResearchPackJSON = #"""
{payload}
"""#
'''
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(content, encoding='utf-8')


def paper_to_label(domain: str) -> str:
    return LABEL_MAP.get(domain, 'travel_design_strategy')


def build_training_rows(rows: List[Dict]) -> List[Dict]:
    training_rows = []
    for row in rows:
        label = paper_to_label(row['domain'])
        title = row['title']
        domain = row['domain']
        insight = row['actionable_insight']
        action = row['action_hint']

        prompts = [
            f"Travel design brief: use evidence from '{title}' to define one next field action for {domain}.",
            f"Research-backed travel design execution request: {insight}",
            f"Translate this scientific finding into Atlas travel design workflow now: {action}",
        ]
        if domain in {'travel', 'mobility', 'recovery', 'health', 'wellbeing', 'skill-building', 'motivation'}:
            prompts.append(
                "Travel design neuro brief: use controlled novelty plus structured reflection to improve adaptability "
                "and protect long-term cognitive vitality."
            )
        if domain in {
            'emergency-response',
            'emergency-preparedness',
            'emergency-management',
            'crisis-management',
            'crisis-planning',
            'incident-command',
        }:
            prompts.append(
                "Emergency command brief: convert this evidence into a triage-stabilize-communicate-escalate protocol "
                "for immediate field execution."
            )
        if domain in {
            'human-problem-solving',
            'human-performance',
            'biological-performance',
            'environmental-performance',
            'problem-solving',
        }:
            prompts.append(
                "Human problem-solving optimization brief: define biological and environmental conditions that maximize "
                "cognitive throughput under uncertainty."
            )
        if domain in {
            'technology-innovation',
            'systems-innovation',
            'digital-innovation',
            'physical-innovation',
            'innovation',
        }:
            prompts.append(
                "Innovation systems brief: translate this into a digital+physical prototype loop with safety gates and "
                "clear validation metrics."
            )
        for prompt in prompts:
            training_rows.append({
                'prompt': prompt,
                'label': label,
                'next_action': action,
                'paper_id': row['id'],
                'source_url': row['source_url'],
            })
    return training_rows


def write_jsonl(rows: List[Dict], output: Path):
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open('w', encoding='utf-8') as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False) + '\n')


def merge_into_base(base: Path, generated_rows: List[Dict]):
    existing = []
    if base.exists():
        normalized_text = base.read_text(encoding='utf-8').replace('\\n', '\n')
        for raw in normalized_text.splitlines():
            line = raw.strip()
            if line:
                existing.append(json.loads(line))

    prompt_to_index = {}
    for idx, row in enumerate(existing):
        prompt = str(row.get('prompt', '')).strip().lower()
        if prompt:
            prompt_to_index[prompt] = idx

    merged = list(existing)
    added = 0
    updated = 0
    for row in generated_rows:
        key = row['prompt'].strip().lower()
        if key in prompt_to_index:
            idx = prompt_to_index[key]
            changed = False
            if merged[idx].get('label') != row['label']:
                merged[idx]['label'] = row['label']
                changed = True
            if merged[idx].get('next_action') != row['next_action']:
                merged[idx]['next_action'] = row['next_action']
                changed = True
            if changed:
                updated += 1
            continue
        merged.append({
            'prompt': row['prompt'],
            'label': row['label'],
            'next_action': row['next_action'],
        })
        prompt_to_index[key] = len(merged) - 1
        added += 1

    write_jsonl(merged, base)
    return added, updated, len(merged)


def write_report(
    rows: List[Dict],
    training_rows: List[Dict],
    merged_added: int,
    merged_updated: int,
    merged_total: int,
):
    ts = dt.datetime.now(dt.timezone.utc).isoformat()
    by_domain = Counter([r['domain'] for r in rows])
    by_label = Counter([paper_to_label(r['domain']) for r in rows])

    report = [
        '# Swift Scientific Corpus Build Report',
        '',
        f'- Generated at (UTC): {ts}',
        f'- Scientific papers loaded: {len(rows)}',
        f'- Research-derived training rows generated: {len(training_rows)}',
        f'- Rows merged into base local_reasoner_training.jsonl: {merged_added}',
        f'- Existing rows updated in base local_reasoner_training.jsonl: {merged_updated}',
        f'- Base local_reasoner_training.jsonl total rows: {merged_total}',
        '',
        '## Domain coverage',
        '',
        '| Domain | Count |',
        '| --- | ---: |',
    ]
    for domain, count in sorted(by_domain.items()):
        report.append(f'| {domain} | {count} |')

    report.extend([
        '',
        '## Label mapping coverage',
        '',
        '| Label | Count |',
        '| --- | ---: |',
    ])
    for label, count in sorted(by_label.items()):
        report.append(f'| {label} | {count} |')

    report.extend([
        '',
        '## Outputs',
        '',
        f'- iOS research pack: `{IOS_PACK}`',
        f'- macOS research pack: `{MAC_PACK}`',
        f'- generated science training rows: `{SCI_TRAINING}`',
        f'- report: `{REPORT}`',
        '',
        '## Next step',
        '',
        'Run local training to update Swift model payloads:',
        '',
        '```bash',
        'cd /Users/avrohom/Downloads/journeyatlas',
        './scripts/train-local-model-loop.sh',
        '```',
    ])

    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text('\n'.join(report) + '\n', encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description='Build Swift app research corpus + derived local training rows.')
    parser.add_argument('--input', nargs='+', default=[str(DEFAULT_INPUT)], help='JSONL files with paper records')
    parser.add_argument('--max-papers', type=int, default=5000)
    parser.add_argument('--merge-into-base', action='store_true', help='merge generated rows into base training dataset')
    args = parser.parse_args()

    inputs = [Path(p).expanduser().resolve() for p in args.input]
    papers = load_jsonl(inputs)
    papers = papers[: max(1, args.max_papers)]

    to_swift_pack(papers, IOS_PACK)
    to_swift_pack(papers, MAC_PACK)

    training_rows = build_training_rows(papers)
    write_jsonl(training_rows, SCI_TRAINING)

    merged_added, merged_updated, merged_total = 0, 0, len(training_rows)
    if args.merge_into_base:
        merged_added, merged_updated, merged_total = merge_into_base(BASE_TRAINING, training_rows)

    write_report(papers, training_rows, merged_added, merged_updated, merged_total)

    print(f'loaded_papers={len(papers)}')
    print(f'generated_training_rows={len(training_rows)}')
    if args.merge_into_base:
        print(f'merged_added={merged_added}')
        print(f'merged_updated={merged_updated}')
        print(f'base_total={merged_total}')
    print(f'ios_pack={IOS_PACK}')
    print(f'macos_pack={MAC_PACK}')
    print(f'report={REPORT}')


if __name__ == '__main__':
    main()
