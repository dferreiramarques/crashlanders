"""Build crashlanders.zip for PortMaster (drop it in PortMaster's autoinstall folder).

    python muos/build_zip.py

Writes muos/dist/crashlanders.zip with the launcher, port.json and the game folder,
and copies it to guia/downloads/ for the product page.
Line endings in .sh/.lua/.json are forced to LF (CRLF gives a black screen on device).
"""
import os
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "dist")
TEXT = (".sh", ".lua", ".json", ".txt", ".md")


def add(zf, src, arc):
    if src.endswith(TEXT):
        with open(src, "rb") as f:
            data = f.read().replace(b"\r\n", b"\n")
        info = zipfile.ZipInfo(arc)
        info.compress_type = zipfile.ZIP_DEFLATED
        if src.endswith(".sh"):
            info.external_attr = 0o755 << 16
        else:
            info.external_attr = 0o644 << 16
        zf.writestr(info, data)
    else:
        zf.write(src, arc)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    out = os.path.join(OUT_DIR, "crashlanders.zip")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        add(zf, os.path.join(HERE, "Crashlanders.sh"), "Crashlanders.sh")
        game = os.path.join(HERE, "crashlanders")
        for root, _, files in os.walk(game):
            for name in files:
                if name in ("log.txt",) or root.split(os.sep)[-1] == "conf":
                    continue
                src = os.path.join(root, name)
                arc = os.path.relpath(src, HERE).replace(os.sep, "/")
                add(zf, src, arc)
    print("wrote", out)
    # Copy next to the product page so its download button serves the latest build
    page_dl = os.path.join(HERE, "..", "guia", "downloads")
    if os.path.isdir(os.path.join(HERE, "..", "guia")):
        os.makedirs(page_dl, exist_ok=True)
        import shutil
        shutil.copyfile(out, os.path.join(page_dl, "crashlanders.zip"))
        print("copied to", os.path.normpath(os.path.join(page_dl, "crashlanders.zip")))


if __name__ == "__main__":
    main()
