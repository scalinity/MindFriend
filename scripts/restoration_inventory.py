#!/usr/bin/env python3
"""Build a metadata-only restoration inventory from the protected snapshot and source.

No database/provider calls, credentials or user records are read by this inventory.
Static references are evidence of use; absence is explicitly not evidence of abandonment.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--evidence", type=Path, required=True)
parser.add_argument("--recovery", type=Path, required=True)
parser.add_argument("--baseline", default="HEAD", help="Git commit to compare with the protected snapshot (default: HEAD)")
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
resolved_baseline = subprocess.run(
    ["git", "rev-parse", "--verify", args.baseline + "^{commit}"],
    cwd=root, capture_output=True, text=True,
)
if resolved_baseline.returncode != 0:
    parser.error("The baseline must resolve to an available Git commit")
baseline_commit = resolved_baseline.stdout.strip()

def read_json(name):
    return json.loads((args.evidence / name).read_text())

swift = {str(p.relative_to(root)): p.read_text() for p in (root / "apps/ios/MindFriendApp").rglob("*.swift")}
constants = dict(re.findall(r'static let (\w+)\s*=\s*"([\w-]+)"', swift["apps/ios/MindFriendApp/Networking/SupabaseClient.swift"]))
refs = {kind: {} for kind in ["table", "rpc", "function", "bucket", "realtime"]}
dynamic = []
for path, source in swift.items():
    for kind, pattern in [
        ("table", r'\.from\(\s*"([\w-]+)"'),
        ("rpc", r'\.rpc\(\s*"([\w-]+)"'),
        ("function", r'\.invoke\(\s*"([\w-]+)"'),
        ("realtime", r'(?s)(?:postgresChange|onPostgresChange)\(.{0,250}?table:\s*"([\w-]+)"'),
    ]:
        for name in re.findall(pattern, source):
            refs[kind].setdefault(name, []).append(path)
    for name in re.findall(r'\.from\(\s*Tables\.(\w+)', source):
        if name in constants:
            refs["table"].setdefault(constants[name], []).append(path)
    for name in re.findall(r'(?s)(?:postgresChange|onPostgresChange)\(.{0,250}?table:\s*Tables\.(\w+)', source):
        if name in constants:
            refs["realtime"].setdefault(constants[name], []).append(path)
    for match in re.finditer(r'(?s)\.storage\s*\.from\(\s*"([\w-]+)"', source):
        refs["bucket"].setdefault(match[1], []).append(path)
    if re.search(r'\.invoke\(\s*[a-zA-Z_]\w*\s*[,)]', source):
        dynamic.append(path)

tables = read_json("inventory.json")
deployed = read_json("deployed_functions.json")["functions"]
workloads = read_json("workloads.json")[0]["metadata"]
cron_targets = {j["edge_target"] for j in workloads["jobs"] if j["edge_target"]}
core_tables = {"profiles", "user_settings", "user_stats", "conversations", "messages", "voice_sessions", "voice_usage", "subscriptions", "agent_actions"}
for table in tables:
    name = table["relname"]
    table["app_references"] = sorted(set(refs["table"].get(name, [])))
    table["category"] = "critical" if name in core_tables else "used" if table["app_references"] else "uncertain"

functions = []
for function in deployed:
    slug = function["slug"]
    local = root / "supabase/functions" / slug / "index.ts"
    snapshot = args.recovery / "deployed/supabase/functions" / slug / "index.ts"
    baseline_result = subprocess.run(
        ["git", "show", baseline_commit + ":supabase/functions/" + slug + "/index.ts"],
        cwd=root, capture_output=True,
    )
    baseline = baseline_result.stdout if baseline_result.returncode == 0 else None
    deployed_source = snapshot.read_bytes() if snapshot.exists() else None
    source = deployed_source.decode() if deployed_source else ""
    category = "critical" if slug in {"chat", "voice-token", "voice-session-end", "delete-account"} else "used" if refs["function"].get(slug) or slug in cron_targets else "uncertain"
    functions.append({
        "slug": slug, "version": function["version"], "verify_jwt": function.get("verify_jwt"), "status": function["status"],
        "category": category, "local_entrypoint": local.exists(), "deployed_source_exported": snapshot.exists(),
        "baseline_source_available": baseline is not None,
        "baseline_exact_match": baseline == deployed_source if baseline is not None and deployed_source is not None else None,
        "baseline_sha256": hashlib.sha256(baseline).hexdigest() if baseline is not None else None,
        "deployed_sha256": hashlib.sha256(deployed_source).hexdigest() if deployed_source is not None else None,
        "app_references": sorted(set(refs["function"].get(slug, []))), "scheduled": slug in cron_targets,
        "auth_indicators": {"getUser": "auth.getUser" in source, "cron_secret": "CRON_SECRET" in source, "service_key": "SUPABASE_SERVICE_ROLE_KEY" in source},
        "auth_review": "manual review required; gateway flag and string indicators do not establish authorization",
        "secret_names_referenced": sorted(set(re.findall(r'Deno.env.get\("([A-Z0-9_]+)"\)', source))),
    })

definers = []
for function in read_json("security.json"):
    signature, body = function["signature"], function["definition"]
    name = signature.split("(")[0]
    definers.append({
        "signature": signature, "anon_execute": function["anon_exec"], "authenticated_execute": function["authenticated_exec"],
        "search_path": function["proconfig"], "trigger_only": bool(re.search(r'RETURNS trigger', body, re.I)),
        "app_references": sorted(set(refs["rpc"].get(name, []))),
        "caller_supplied_user_id": "p_user_id" in body,
        "visible_uid_check": "auth.uid()" in body,
        "review": "needs manual ownership and privilege review",
    })

for bucket in workloads["buckets"]:
    bucket["app_references"] = sorted(set(refs["bucket"].get(bucket["name"], [])))
    bucket["privacy_review"] = "public object URLs bypass object SELECT policies" if bucket["public"] else "private; signed-download and ownership tests required"

out = {
    "project_ref": "zfaucivtzfwnrijsbfug", "baseline_commit": baseline_commit,
    "classification_rule": "critical core path; used means static app or scheduled reference; uncertain means no direct static reference. No component is authorized for deletion.",
    "limitations": ["Static references miss dynamic function/table names and server-side indirect callers.", "Source equality is byte equality against baseline, not a semantic equivalence claim.", "Object content and real user records are excluded."],
    "tables_and_views": tables, "edge_functions": functions, "security_definers": definers,
    "buckets": workloads["buckets"], "cron_jobs": workloads["jobs"], "cron_observed_runs": workloads["runs"],
    "realtime_published_tables": workloads["published_tables"] or [], "app_references": refs, "dynamic_function_call_files": dynamic,
    "advisors": {kind: [{"name": x["name"], "count": x["count"], "remediation": x["remediation"]} for x in read_json("advisor_" + kind + "-parsed.json")["lints"]] for kind in ["security", "performance"]},
}
destination = args.evidence / "backend-inventory.json"
destination.write_text(json.dumps(out, indent=2))
print(json.dumps({"tables_and_views": len(tables), "edge_functions": len(functions), "definers": len(definers), "buckets": len(workloads["buckets"]), "jobs": len(workloads["jobs"]), "referenced_tables": len(refs["table"]), "referenced_functions": len(refs["function"]), "referenced_rpcs": len(refs["rpc"]), "realtime_tables": list(refs["realtime"]), "deployed_only": [f["slug"] for f in functions if not f["local_entrypoint"]], "exact_source_matches": sum(f["baseline_exact_match"] is True for f in functions)}, indent=2))
