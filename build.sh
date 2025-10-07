#!/bin/bash
#
# Munki Build Script with YAML Support
# Builds and signs all Munki tools using Xcode
#
# Usage:
#   ./build.sh                    # Build unsigned package
#   ./build.sh --sign             # Build and sign package
#   ./build.sh --sign --notarize  # Build, sign, and notarize package
#

set -e  # Exit on error

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Load configuration from .env file
if [ -f "$SCRIPT_DIR/.env" ]; then
    echo -e "${BLUE}Loading configuration from .env...${NC}"
    # Export variables from .env, ignoring comments and empty lines
    export $(grep -v '^#' "$SCRIPT_DIR/.env" | grep -v '^[[:space:]]*$' | xargs)
    echo -e "${GREEN}✓${NC} Configuration loaded"
    echo ""
else
    echo -e "${YELLOW}⚠ No .env file found${NC}"
    echo -e "  Using default values (may not work for signing/notarization)"
    echo -e "  Copy .env.example to .env and configure your certificates"
    echo ""
fi

# Default options
SIGN=false
NOTARIZE=false
OUTPUT_DIR="${OUTPUT_DIR:-$HOME/Desktop}"

# Certificate identifiers (can be overridden by .env)
APP_SIGNING_CERT="${APP_SIGNING_CERT:-}"
PKG_SIGNING_CERT="${PKG_SIGNING_CERT:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-NOTARY_PROFILE}"
TEAM_ID="${TEAM_ID:-}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --sign|-s)
            SIGN=true
            shift
            ;;
        --notarize|-n)
            NOTARIZE=true
            SIGN=true  # Notarization requires signing
            shift
            ;;
        --output|-o)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --sign, -s           Sign the package with Developer ID certificates"
            echo "  --notarize, -n       Sign and notarize the package (requires Apple ID setup)"
            echo "  --output DIR, -o     Output directory (default: ~/Desktop)"
            echo "  --help, -h           Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                      # Build unsigned package"
            echo "  $0 --sign               # Build and sign package"
            echo "  $0 --sign --notarize    # Build, sign, and notarize"
            echo "  $0 -s -o ~/Downloads    # Sign and save to Downloads"
            echo ""
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Create output directory if it doesn't exist
mkdir -p "$OUTPUT_DIR"

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║          Munki Build Script - YAML Support Enabled         ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Build options
BUILD_OPTS="-o $OUTPUT_DIR"
if [ "$SIGN" = true ]; then
    if [ -z "$APP_SIGNING_CERT" ] || [ -z "$PKG_SIGNING_CERT" ]; then
        echo -e "${RED}✗ Signing certificates not configured${NC}"
        echo -e "  Create a .env file with APP_SIGNING_CERT and PKG_SIGNING_CERT"
        echo -e "  See .env.example for template"
        exit 1
    fi
    echo -e "${GREEN}✓${NC} Code signing: ENABLED"
    echo -e "  App signing cert: ${APP_SIGNING_CERT:0:8}..."
    echo -e "  Pkg signing cert: ${PKG_SIGNING_CERT:0:8}..."
    BUILD_OPTS="$BUILD_OPTS -S $APP_SIGNING_CERT -s $PKG_SIGNING_CERT"
else
    echo -e "${YELLOW}○${NC} Code signing: DISABLED"
fi

if [ "$NOTARIZE" = true ]; then
    if [ -z "$NOTARY_PROFILE" ]; then
        echo -e "${RED}✗ Notarization profile not configured${NC}"
        echo -e "  Set NOTARY_PROFILE in .env file"
        exit 1
    fi
    echo -e "${GREEN}✓${NC} Notarization: ENABLED"
    echo -e "  Profile: $NOTARY_PROFILE"
    if [ -n "$TEAM_ID" ]; then
        echo -e "  Team ID: $TEAM_ID"
    fi
else
    echo -e "${YELLOW}○${NC} Notarization: DISABLED"
fi

echo -e "  Output directory: $OUTPUT_DIR"
echo ""

# Check for required tools
echo -e "${BLUE}Checking build requirements...${NC}"
if ! command -v xcodebuild &> /dev/null; then
    echo -e "${RED}✗ xcodebuild not found${NC}"
    echo "  Please install Xcode Command Line Tools"
    exit 1
fi
echo -e "${GREEN}✓${NC} xcodebuild found"

if ! command -v git &> /dev/null; then
    echo -e "${RED}✗ git not found${NC}"
    exit 1
fi
echo -e "${GREEN}✓${NC} git found"

# Check for certificates if signing
if [ "$SIGN" = true ]; then
    if [ -z "$APP_SIGNING_CERT" ]; then
        echo -e "${RED}✗ APP_SIGNING_CERT not set${NC}"
        echo "  Configure in .env file"
        exit 1
    fi
    
    if ! security find-identity -v -p codesigning | grep -q "$APP_SIGNING_CERT"; then
        echo -e "${RED}✗ App signing certificate not found in keychain${NC}"
        echo "  Looking for: $APP_SIGNING_CERT"
        echo ""
        echo "  Available certificates:"
        security find-identity -v -p codesigning | grep "Developer ID"
        exit 1
    fi
    echo -e "${GREEN}✓${NC} App signing certificate found"
    
    if [ -z "$PKG_SIGNING_CERT" ]; then
        echo -e "${RED}✗ PKG_SIGNING_CERT not set${NC}"
        echo "  Configure in .env file"
        exit 1
    fi
    
    if ! security find-identity -v -p basic | grep -q "$PKG_SIGNING_CERT"; then
        echo -e "${RED}✗ Package signing certificate not found in keychain${NC}"
        echo "  Looking for: $PKG_SIGNING_CERT"
        echo ""
        echo "  Available certificates:"
        security find-identity -v -p basic | grep "Developer ID"
        exit 1
    fi
    echo -e "${GREEN}✓${NC} Package signing certificate found"
fi

# Check for notarization credentials if notarizing
if [ "$NOTARIZE" = true ]; then
    if [ -z "$NOTARY_PROFILE" ]; then
        echo -e "${RED}✗ NOTARY_PROFILE not set in .env${NC}"
        exit 1
    fi
    
    if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" &> /dev/null; then
        echo -e "${RED}✗ Notarization credentials not found${NC}"
        echo ""
        echo "  Set up notarization with:"
        TEAM_DISPLAY="${TEAM_ID:-YOUR_TEAM_ID}"
        echo "    xcrun notarytool store-credentials \"$NOTARY_PROFILE\" \\"
        echo "      --apple-id \"your-apple-id@example.com\" \\"
        echo "      --team-id \"$TEAM_DISPLAY\" \\"
        echo "      --password \"app-specific-password\""
        echo ""
        echo "  Generate app-specific password at: https://appleid.apple.com"
        echo ""
        echo "  Then update .env with:"
        echo "    NOTARY_PROFILE=\"$NOTARY_PROFILE\""
        echo "    TEAM_ID=\"$TEAM_DISPLAY\""
        exit 1
    fi
    echo -e "${GREEN}✓${NC} Notarization credentials found"
fi

echo ""
echo -e "${BLUE}Building Munki package...${NC}"
echo ""

# Run the build
LOG_FILE="/tmp/munki_build_$(date +%Y%m%d_%H%M%S).log"
if bash code/tools/make_swift_munki_pkg.sh $BUILD_OPTS 2>&1 | tee "$LOG_FILE"; then
    echo ""
    echo -e "${GREEN}✓ Build completed successfully${NC}"
    
    # Extract package name from log
    PKG_NAME=$(grep "Distribution package created at" "$LOG_FILE" | awk -F'/' '{print $NF}' | sed 's/\.$//')
    PKG_PATH="$OUTPUT_DIR/$PKG_NAME"
    
    if [ -f "$PKG_PATH" ]; then
        PKG_SIZE=$(du -h "$PKG_PATH" | awk '{print $1}')
        echo -e "  Package: ${GREEN}$PKG_NAME${NC}"
        echo -e "  Size: $PKG_SIZE"
        echo -e "  Location: $PKG_PATH"
        
        # Get version info
        VERSION=$(echo "$PKG_NAME" | sed 's/munkitools-//;s/.pkg//')
        echo -e "  Version: $VERSION"
        
        # Verify signature if signed
        if [ "$SIGN" = true ]; then
            echo ""
            echo -e "${BLUE}Verifying signature...${NC}"
            if pkgutil --check-signature "$PKG_PATH" | grep -q "signed by a developer certificate"; then
                echo -e "${GREEN}✓ Package signature verified${NC}"
            else
                echo -e "${RED}✗ Package signature verification failed${NC}"
                exit 1
            fi
        fi
        
        # Notarize if requested
        if [ "$NOTARIZE" = true ]; then
            echo ""
            echo -e "${BLUE}Submitting for notarization...${NC}"
            echo -e "${YELLOW}⏳ This may take several minutes...${NC}"
            
            if xcrun notarytool submit "$PKG_PATH" \
                --keychain-profile "$NOTARY_PROFILE" \
                --wait 2>&1 | tee /tmp/notarize.log; then
                
                echo ""
                echo -e "${GREEN}✓ Notarization completed${NC}"
                
                echo -e "${BLUE}Stapling notarization ticket...${NC}"
                if xcrun stapler staple "$PKG_PATH"; then
                    echo -e "${GREEN}✓ Notarization ticket stapled${NC}"
                    echo ""
                    echo -e "${GREEN}✓ Package is ready for distribution!${NC}"
                else
                    echo -e "${YELLOW}⚠ Stapling failed, but package is notarized${NC}"
                fi
            else
                echo -e "${RED}✗ Notarization failed${NC}"
                echo "  Check /tmp/notarize.log for details"
                exit 1
            fi
        fi
        
        echo ""
        echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
        echo -e "${GREEN}Build Summary${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
        echo ""
        
        # Extract version info from log
        CORE_VERSION=$(grep "munki core tools version:" "$LOG_FILE" | awk '{print $5}')
        APP_VERSION=$(grep "Apps package version:" "$LOG_FILE" | awk '{print $4}')
        
        echo -e "  ${GREEN}✓${NC} Core tools:     $CORE_VERSION"
        echo -e "  ${GREEN}✓${NC} Applications:   $APP_VERSION"
        echo -e "  ${GREEN}✓${NC} Package:        $PKG_NAME"
        echo ""
        echo -e "${BLUE}YAML Support:${NC}"
        echo -e "  ${GREEN}✓${NC} makepkginfo convert    (pkginfo file conversion)"
        echo -e "  ${GREEN}✓${NC} manifestutil convert   (manifest file conversion)"
        echo -e "  ${GREEN}✓${NC} Native YAML support    (all tools)"
        echo ""
        
        if [ "$SIGN" = true ]; then
            echo -e "${BLUE}Signing:${NC}"
            echo -e "  ${GREEN}✓${NC} Code signed with Developer ID"
            echo -e "  ${GREEN}✓${NC} Package signed with Developer ID"
        fi
        
        if [ "$NOTARIZE" = true ]; then
            echo -e "${BLUE}Notarization:${NC}"
            echo -e "  ${GREEN}✓${NC} Notarized by Apple"
            echo -e "  ${GREEN}✓${NC} Ready for distribution"
        fi
        
        echo ""
        echo -e "${BLUE}Installation:${NC}"
        echo -e "  sudo installer -pkg \"$PKG_PATH\" -target /"
        echo ""
        echo -e "${BLUE}Build log:${NC} $LOG_FILE"
        echo ""
        
    else
        echo -e "${RED}✗ Package file not found${NC}"
        exit 1
    fi
else
    echo ""
    echo -e "${RED}✗ Build failed${NC}"
    echo -e "  Check log: $LOG_FILE"
    exit 1
fi
