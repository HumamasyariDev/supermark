"""W2 builder tool: append one evidence row to data/evidence.jsonl (TECH_CONTRACT fields).

python game/assets/environment/w2/tools/w2_evidence.py <file relative to the entity> "<caption>" "<observed>" [capture_type]
"""
import datetime, hashlib, json, os, sys

ENT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", ".."))


def main():
    rel, caption, observed = sys.argv[1], sys.argv[2], sys.argv[3]
    ctype = sys.argv[4] if len(sys.argv) > 4 else "native_viewport"
    path = os.path.join(ENT, rel)
    sha = hashlib.sha256(open(path, "rb").read()).hexdigest() if os.path.exists(path) else None
    row = {
        "utc": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "timezone": "Asia/Bangkok",
        "run": "night01",
        "milestone": "night01-w2",
        "feature": "w2",
        "capture_type": ctype,
        "file": rel.replace("\\", "/"),
        "sha256": sha,
        "caption": caption,
        "observed": observed,
        "reviewed": True,
    }
    with open(os.path.join(ENT, "data", "evidence.jsonl"), "a", encoding="utf-8") as f:
        f.write(json.dumps(row) + "\n")
    print("evidence row:", row["file"], sha[:12] if sha else None)


if __name__ == "__main__":
    main()
