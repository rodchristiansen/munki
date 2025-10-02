#!/usr/bin/env python3

import os
import sys

# Add the deployment directory to test with real data
sys.path.insert(0, '/Users/rod/DevOps/Munki/deployment')

try:
    import makecatalogs
    print("Testing YAML generation with existing makecatalogs...")
    
    # Test in the deployment directory
    os.chdir('/Users/rod/DevOps/Munki/deployment')
    
    # Try to run makecatalogs with YAML output
    sys.argv = ['makecatalogs', '--yaml', '--skip-pkg-check']
    
    print("Running makecatalogs with YAML support...")
    makecatalogs.main()
    
except Exception as e:
    print(f"Error: {e}")
    print("This confirms we need our Swift YAML fixes!")

# Test specific problematic object serialization
print("\nTesting YAML serialization of problematic objects...")

import yaml
from pprint import pprint

# Create test objects that might cause issues
test_objects = {
    'string_path': 'prefs/curriculum/SetDisplayResolution-15.6.1.pkg',
    'complex_object': {
        'nested': {
            'path': 'some/file/path.pkg'
        }
    }
}

try:
    yaml_output = yaml.dump(test_objects, default_flow_style=False)
    print("✅ Basic YAML serialization works:")
    print(yaml_output)
except Exception as e:
    print(f"❌ YAML serialization failed: {e}")
