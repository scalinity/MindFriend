"""Package only public website files; auth experiments and workflow files stay private."""
import hashlib
import json
from pathlib import Path
import sys
import tarfile

root = Path(__file__).resolve().parents[1]
files = [
    "index.html", "privacy/index.html", "terms/index.html",
    "support/index.html", "accessibility/index.html",
    "css/home.css", "css/legal.css",
    "assets/logo.png", "assets/app-screenshot.jpg", "licenses/tailwindcss.txt",
]
manifest = {}
with tarfile.open(sys.argv[1], "x:gz") as archive:
    for name in files:
        path = root / name
        assert path.is_file() and not path.is_symlink(), name
        manifest[name] = hashlib.sha256(path.read_bytes()).hexdigest()
        archive.add(path, arcname=name)
Path(sys.argv[1] + ".manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
