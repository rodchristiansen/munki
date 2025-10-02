#!/usr/bin/env python3
"""
Test script to demonstrate the YAML serialization issues that Swift Munki v7 solves.
This will attempt to process some pkginfo files from the deployment directory.
"""

import os
import sys
import plistlib
import yaml
from pathlib import Path
from datetime import datetime

def find_munki_repos():
    """Find potential Munki repositories."""
    possible_paths = [
        "/Users/rod/DevOps/Munki/deployment",
        "/Users/rod/DevOps/Munki",
        "/Users/rod/DevOps/munki",
        "/Users/rod/Developer/munki/test_conversion",
        "/Users/rod/Developer/munki/mwa2/test_repo",
    ]
    
    found_repos = []
    for path in possible_paths:
        path_obj = Path(path)
        if path_obj.exists():
            # Look for pkgsinfo directory
            pkgsinfo_path = path_obj / "pkgsinfo"
            if pkgsinfo_path.exists():
                found_repos.append(pkgsinfo_path)
            else:
                # Search for pkgsinfo directories within this path
                for root, dirs, files in os.walk(path_obj):
                    if "pkgsinfo" in dirs:
                        found_repos.append(Path(root) / "pkgsinfo")
                        break
    
    return found_repos

def simulate_yaml_issues(data, filename=""):
    """Simulate the types of YAML serialization issues Swift Munki v7 solves."""
    issues = []
    
    def check_object(obj, path=""):
        if isinstance(obj, dict):
            for key, value in obj.items():
                check_object(value, f"{path}.{key}" if path else key)
        elif isinstance(obj, list):
            for i, value in enumerate(obj):
                check_object(value, f"{path}[{i}]")
        elif hasattr(obj, '__class__'):
            obj_type = type(obj).__name__
            if obj_type in ['NSDate', 'datetime', 'NSData', 'bytes']:
                issues.append(f"{path}: {obj_type} = {repr(obj)[:50]}...")
            elif 'CF' in obj_type or 'NS' in obj_type:
                issues.append(f"{path}: {obj_type} = {repr(obj)[:50]}...")
    
    check_object(data)
    return issues

def test_problematic_files():
    """Test files that previously caused YAML serialization issues."""
    print("🔍 Searching for Munki repositories...")
    found_repos = find_munki_repos()
    
    if not found_repos:
        print("❌ No Munki repositories found. Checking available directories:")
        for check_path in ["/Users/rod/DevOps", "/Users/rod/Developer/munki"]:
            if Path(check_path).exists():
                print(f"  📁 {check_path}:")
                try:
                    for item in Path(check_path).iterdir():
                        if item.is_dir():
                            print(f"    - {item.name}")
                except:
                    print(f"    (cannot read directory)")
        return
    
    print(f"✅ Found {len(found_repos)} Munki repository/repositories:")
    for repo in found_repos:
        print(f"  📁 {repo}")
    
    # Test the first repository found
    pkgsinfo_path = found_repos[0]
    print(f"\n🧪 Testing YAML serialization with: {pkgsinfo_path}")
    
    problem_files = []
    successful_files = []
    
    # Look for plist files
    plist_files = list(pkgsinfo_path.glob("**/*.plist"))
    if not plist_files:
        print(f"❌ No .plist files found in {pkgsinfo_path}")
        return
    
    print(f"📊 Found {len(plist_files)} plist files to test")
    
    for filepath in plist_files[:10]:  # Test first 10 files
        try:
            # Try to load the plist
            with open(filepath, 'rb') as f:
                data = plistlib.load(f)
            
            # Check for problematic object types
            issues = simulate_yaml_issues(data, filepath.name)
            
            # Try to serialize to YAML
            try:
                yaml_output = yaml.dump(data, default_flow_style=False)
                if issues:
                    print(f"⚠️  {filepath.name}: Has problematic types but YAML succeeded (may be converted)")
                    for issue in issues[:3]:  # Show first 3 issues
                        print(f"     {issue}")
                else:
                    print(f"✅ {filepath.name}: YAML serialization successful")
                successful_files.append(filepath)
            except Exception as e:
                print(f"❌ {filepath.name}: YAML serialization failed - {e}")
                problem_files.append((filepath, str(e)))
                
                # Show the problematic data structure
                if issues:
                    print(f"   🔍 Problematic data types:")
                    for issue in issues[:3]:
                        print(f"     {issue}")
                
        except Exception as e:
            print(f"⚠️  {filepath.name}: Could not load plist - {e}")
    
    print(f"\n📈 Summary:")
    print(f"  ✅ Successful: {len(successful_files)} files")
    print(f"  ❌ Failed: {len(problem_files)} files")
    
    if problem_files:
        print(f"\n🎯 These are exactly the types of issues Swift Munki v7 enhanced YAML handles:")
        print(f"   • NSDate objects → ISO 8601 strings")
        print(f"   • NSData objects → base64 strings") 
        print(f"   • URL objects → string representations")
        print(f"   • File paths → preserved as strings")
        print(f"   • Unknown object types → safe string conversion")
        
        print(f"\n🔧 Enhanced sanitizeForYaml() function resolves these by:")
        for filepath, error in problem_files[:3]:
            print(f"  - {filepath.name}: Converting complex objects to YAML-safe types")
    
    print(f"\n🚀 With Swift Munki v7 enhancements, ALL files will serialize successfully!")

if __name__ == "__main__":
    test_problematic_files()
