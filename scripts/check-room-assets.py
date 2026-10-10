"""Verify copied OBJ/MTL/texture/license resources in either SwiftPM bundle layout."""
import pathlib
import re
import sys

bundle = pathlib.Path(sys.argv[1]) / "Contents/Resources/LofiMen_LofiMen.bundle"
resources = bundle / "Contents/Resources" if (bundle / "Contents/Resources").is_dir() else bundle
folder = resources / "RoomFurniture"
source = pathlib.Path("Sources/LofiMen/Resources/RoomFurniture")
for original in source.iterdir():
    copied = folder / original.name
    assert copied.is_file() and copied.read_bytes() == original.read_bytes(), f"Missing or altered room asset: {original.name}"
    if original.suffix == ".obj":
        for name in re.findall(r"^mtllib (.+)$", original.read_text(), re.MULTILINE):
            assert (folder / name).is_file(), f"Missing material library: {name}"
    if original.suffix == ".mtl":
        for name in re.findall(r"^map_Kd (.+)$", original.read_text(), re.MULTILINE):
            assert (folder / name).is_file(), f"Missing furniture texture: {name}"
assert "CC0" in (folder / "LICENSE.txt").read_text()
print("Room models, material libraries, texture and CC0 license are bundled intact.")
