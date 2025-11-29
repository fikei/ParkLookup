#!/usr/bin/env python3
"""Script to add blockface files to Xcode project"""

import re

project_path = "/home/user/ParkLookup/SFParkingZoneFinder/SFParkingZoneFinder.xcodeproj/project.pbxproj"

# Read the project file
with open(project_path, 'r') as f:
    content = f.read()

# Generate unique IDs for new files
blockface_model_ref = "3CBD00012EDBF000001BDE61"
blockface_model_build = "3CBD00022EDBF000001BDE61"

blockface_overlays_ref = "3CBD00032EDBF000001BDE61"
blockface_overlays_build = "3CBD00042EDBF000001BDE61"

blockface_loader_ref = "3CBD00052EDBF000001BDE61"
blockface_loader_build = "3CBD00062EDBF000001BDE61"

sample_json_ref = "3CBD00072EDBF000001BDE61"
sample_json_build = "3CBD00082EDBF000001BDE61"

# 1. Add PBXBuildFile entries
build_file_section = re.search(r'(\/\* Begin PBXBuildFile section \*\/\n)', content)
if build_file_section:
    insert_pos = build_file_section.end()
    new_entries = f"""\t\t{blockface_model_build} /* Blockface.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {blockface_model_ref} /* Blockface.swift */; }};
\t\t{blockface_overlays_build} /* BlockfaceMapOverlays.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {blockface_overlays_ref} /* BlockfaceMapOverlays.swift */; }};
\t\t{blockface_loader_build} /* BlockfaceLoader.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {blockface_loader_ref} /* BlockfaceLoader.swift */; }};
\t\t{sample_json_build} /* sample_blockfaces.json in Resources */ = {{isa = PBXBuildFile; fileRef = {sample_json_ref} /* sample_blockfaces.json */; }};
"""
    content = content[:insert_pos] + new_entries + content[insert_pos:]

# 2. Add PBXFileReference entries
file_ref_section = re.search(r'(\/\* Begin PBXFileReference section \*\/\n)', content)
if file_ref_section:
    insert_pos = file_ref_section.end()
    new_entries = f"""\t\t{blockface_model_ref} /* Blockface.swift */ = {{isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = Blockface.swift; sourceTree = "<group>"; }};
\t\t{blockface_overlays_ref} /* BlockfaceMapOverlays.swift */ = {{isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = BlockfaceMapOverlays.swift; sourceTree = "<group>"; }};
\t\t{blockface_loader_ref} /* BlockfaceLoader.swift */ = {{isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = sourcecode.swift; path = BlockfaceLoader.swift; sourceTree = "<group>"; }};
\t\t{sample_json_ref} /* sample_blockfaces.json */ = {{isa = PBXFileReference; fileEncoding = 4; lastKnownFileType = text.json; path = sample_blockfaces.json; sourceTree = "<group>"; }};
"""
    content = content[:insert_pos] + new_entries + content[insert_pos:]

# 3. Add to Models group (for Blockface.swift)
models_group = re.search(r'(3C4145C62ED14A6F001BDE61 \/\* Models \*\/ = \{\n\s+isa = PBXGroup;\n\s+children = \(\n)', content)
if models_group:
    insert_pos = models_group.end()
    new_entry = f"\t\t\t\t{blockface_model_ref} /* Blockface.swift */,\n"
    content = content[:insert_pos] + new_entry + content[insert_pos:]

# 4. Add to Services group (for BlockfaceLoader.swift)
services_group = re.search(r'(3C4145D62ED14A6F001BDE61 \/\* Services \*\/ = \{\n\s+isa = PBXGroup;\n\s+children = \(\n)', content)
if services_group:
    insert_pos = services_group.end()
    new_entry = f"\t\t\t\t{blockface_loader_ref} /* BlockfaceLoader.swift */,\n"
    content = content[:insert_pos] + new_entry + content[insert_pos:]

# 5. Add to Map/Views group (for BlockfaceMapOverlays.swift)
map_views_group = re.search(r'(3C41461F2ED15702001BDE61 \/\* Views \*\/ = \{\n\s+isa = PBXGroup;\n\s+children = \(\n)', content)
if map_views_group:
    insert_pos = map_views_group.end()
    new_entry = f"\t\t\t\t{blockface_overlays_ref} /* BlockfaceMapOverlays.swift */,\n"
    content = content[:insert_pos] + new_entry + content[insert_pos:]

# 6. Add to Resources group (for sample_blockfaces.json)
resources_group = re.search(r'(3C4145BB2ED14A6F001BDE61 \/\* Resources \*\/ = \{\n\s+isa = PBXGroup;\n\s+children = \(\n)', content)
if resources_group:
    insert_pos = resources_group.end()
    new_entry = f"\t\t\t\t{sample_json_ref} /* sample_blockfaces.json */,\n"
    content = content[:insert_pos] + new_entry + content[insert_pos:]

# 7. Add to Sources build phase
sources_phase = re.search(r'(3C4144F72ED1413F001BDE61 \/\* Sources \*\/ = \{\n\s+isa = PBXSourcesBuildPhase;\n\s+buildActionMask = \d+;\n\s+files = \(\n)', content)
if sources_phase:
    insert_pos = sources_phase.end()
    new_entries = f"""\t\t\t\t{blockface_model_build} /* Blockface.swift in Sources */,
\t\t\t\t{blockface_overlays_build} /* BlockfaceMapOverlays.swift in Sources */,
\t\t\t\t{blockface_loader_build} /* BlockfaceLoader.swift in Sources */,
"""
    content = content[:insert_pos] + new_entries + content[insert_pos:]

# 8. Add to Resources build phase
resources_phase = re.search(r'(3C4144F92ED1413F001BDE61 \/\* Resources \*\/ = \{\n\s+isa = PBXResourcesBuildPhase;\n\s+buildActionMask = \d+;\n\s+files = \(\n)', content)
if resources_phase:
    insert_pos = resources_phase.end()
    new_entry = f"\t\t\t\t{sample_json_build} /* sample_blockfaces.json in Resources */,\n"
    content = content[:insert_pos] + new_entry + content[insert_pos:]

# Write the modified content back
with open(project_path, 'w') as f:
    f.write(content)

print("✓ Added Blockface.swift to Core/Models")
print("✓ Added BlockfaceMapOverlays.swift to Features/Map/Views")
print("✓ Added BlockfaceLoader.swift to Core/Services")
print("✓ Added sample_blockfaces.json to Resources")
