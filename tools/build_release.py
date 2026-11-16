"""Build the addon zip to upload to CurseForge (or to hand to a friend).

Usage: build_release.py [--out DIR]

Writes DIR/ForeverScout-<version>.zip (default DIR: dist/), with one folder at the root:

    ForeverScout/ForeverScout.toc, ForeverScout.lua, Route.lua, README.md, LICENSE

That is the layout the game expects under Interface/AddOns/. The version comes from the TOC.
Files are taken from the working tree, limited to what git tracks in addon/ForeverScout, and
Route.lua always ships empty: a route loaded locally with map_route.py never ends up in a
release.
"""
import subprocess
import sys
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import map_route  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
ADDON = REPO / "addon" / "ForeverScout"
FOLDER = "ForeverScout"
# Fixed timestamp so the same sources always give the same zip.
ZIP_DATE = (2026, 1, 1, 0, 0, 0)


def addon_version():
    for line in (ADDON / "ForeverScout.toc").read_text(encoding="utf-8").splitlines():
        if line.startswith("## Version:"):
            return line.split(":", 1)[1].strip()
    sys.exit("No '## Version:' line in ForeverScout.toc")


def tracked_files():
    """Names of the files git tracks in the addon folder (so stray local files stay out)."""
    out = subprocess.run(["git", "-C", str(REPO), "ls-files", "addon/ForeverScout"],
                         capture_output=True, text=True, check=True).stdout
    return sorted(Path(line).name for line in out.splitlines() if line.strip())


def release_files():
    """{name in the zip folder: bytes}."""
    files = {}
    for name in tracked_files():
        if name == "Route.lua":
            files[name] = map_route.to_lua(None, "").encode("utf-8")
        else:
            files[name] = (ADDON / name).read_bytes()
    files["LICENSE"] = (REPO / "LICENSE").read_bytes()
    toc = files["ForeverScout.toc"].decode("utf-8")
    listed = [line.strip() for line in toc.splitlines() if line.strip() and not line.startswith("#")]
    missing = [name for name in listed if name not in files]
    if missing:
        sys.exit(f"The TOC lists files that are not in the release: {', '.join(missing)}")
    return files


def build(out_dir):
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / f"{FOLDER}-{addon_version()}.zip"
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as archive:
        for name, data in sorted(release_files().items()):
            info = zipfile.ZipInfo(f"{FOLDER}/{name}", date_time=ZIP_DATE)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            archive.writestr(info, data)
    return path


def main():
    args = sys.argv[1:]
    if "-h" in args or "--help" in args:
        sys.exit(__doc__)
    out = REPO / "dist"
    if "--out" in args:
        i = args.index("--out")
        if i + 1 >= len(args):
            sys.exit("--out needs a directory")
        out = args[i + 1]
    path = build(out)
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
    print(f"{path} ({path.stat().st_size} bytes)")
    for name in names:
        print(f"  {name}")


if __name__ == "__main__":
    main()
