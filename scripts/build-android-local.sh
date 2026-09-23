#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RAMANI_DIR="$ROOT_DIR/ramani-maplibre"
MAVEN_REPO="${HOME}/.m2/repository"

usage() {
  cat <<'EOF'
Build Ramani MapLibre and publish it to the local Maven repository.

This build expects the custom MapLibre Native Vulkan artifact to already be
published locally as org.maplibre.gl:android-sdk-vulkan:13.6.1.

Usage: scripts/build-android-local.sh [options]

Options:
  --maven-repo PATH   Local Maven repository. Default: ~/.m2/repository
  -h, --help          Show this help.
EOF
}

while (($#)); do
  case "$1" in
    --maven-repo)
      if (($# < 2)); then
        echo "Missing value for --maven-repo" >&2
        usage >&2
        exit 2
      fi
      MAVEN_REPO="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

command -v java >/dev/null 2>&1 || {
  echo "java not found in PATH; Java 21 is required" >&2
  exit 1
}

JAVA_VERSION="$(java -version 2>&1 | awk -F '"' '/version/ { print $2; exit }')"
JAVA_MAJOR="${JAVA_VERSION%%.*}"
if [[ "$JAVA_MAJOR" == "1" ]]; then
  JAVA_MAJOR="$(printf '%s' "$JAVA_VERSION" | cut -d. -f2)"
fi
if [[ "$JAVA_MAJOR" != "21" ]]; then
  echo "Java 21 is required; found Java $JAVA_VERSION" >&2
  exit 1
fi

[[ -x "$RAMANI_DIR/gradlew" ]] || {
  echo "Gradle wrapper not found or not executable: $RAMANI_DIR/gradlew" >&2
  exit 1
}

MAVEN_REPO="$(mkdir -p "$MAVEN_REPO" && cd "$MAVEN_REPO" && pwd)"

MAPLIBRE_VERSION="$(sed -n 's/^maplibre-android-sdk = "\([^"]*\)".*/\1/p' "$RAMANI_DIR/gradle/libs.versions.toml" | head -n 1)"
[[ -n "$MAPLIBRE_VERSION" ]] || {
  echo "Could not determine MapLibre version from gradle/libs.versions.toml" >&2
  exit 1
}

MAPLIBRE_ARTIFACT_ID="android-sdk-vulkan"
MAPLIBRE_DIR="$MAVEN_REPO/org/maplibre/gl/$MAPLIBRE_ARTIFACT_ID/$MAPLIBRE_VERSION"
MAPLIBRE_AAR="$MAPLIBRE_DIR/$MAPLIBRE_ARTIFACT_ID-$MAPLIBRE_VERSION.aar"
MAPLIBRE_POM="$MAPLIBRE_DIR/$MAPLIBRE_ARTIFACT_ID-$MAPLIBRE_VERSION.pom"

if [[ ! -f "$MAPLIBRE_AAR" || ! -f "$MAPLIBRE_POM" ]]; then
  echo "Local MapLibre Native artifact not found:" >&2
  echo "  org.maplibre.gl:$MAPLIBRE_ARTIFACT_ID:$MAPLIBRE_VERSION" >&2
  echo "Expected:" >&2
  echo "  $MAPLIBRE_AAR" >&2
  echo >&2
  echo "Build and publish MapLibre Native first:" >&2
  echo "  scripts/build-android-local.sh" >&2
  exit 1
fi

RAMANI_VERSION="$(sed -n 's/^[[:space:]]*version = "\([^"]*\)".*/\1/p' "$RAMANI_DIR/build.gradle.kts" | head -n 1)"
[[ -n "$RAMANI_VERSION" ]] || {
  echo "Could not determine Ramani version from build.gradle.kts" >&2
  exit 1
}

echo "Building Ramani MapLibre"
echo "  version:            $RAMANI_VERSION"
echo "  MapLibre dependency: org.maplibre.gl:$MAPLIBRE_ARTIFACT_ID:$MAPLIBRE_VERSION"
echo "  Maven repo:          $MAVEN_REPO"

cd "$RAMANI_DIR"

# Refresh because the custom MapLibre build may use the same version as an
# artifact available from Maven Central. mavenLocal() is configured first.
./gradlew \
  --refresh-dependencies \
  "-Dmaven.repo.local=$MAVEN_REPO" \
  publishReleasePublicationToMavenLocal

ARTIFACT_ID="ramani-maplibre"
ARTIFACT_DIR="$MAVEN_REPO/org/ramani-maps/$ARTIFACT_ID/$RAMANI_VERSION"
AAR="$ARTIFACT_DIR/$ARTIFACT_ID-$RAMANI_VERSION.aar"
POM="$ARTIFACT_DIR/$ARTIFACT_ID-$RAMANI_VERSION.pom"

[[ -f "$AAR" ]] || {
  echo "Published Ramani AAR not found: $AAR" >&2
  exit 1
}
[[ -f "$POM" ]] || {
  echo "Published Ramani POM not found: $POM" >&2
  exit 1
}

echo
echo "Published successfully:"
echo "  $AAR"
echo
echo "Gradle dependency:"
echo "  implementation(\"org.ramani-maps:$ARTIFACT_ID:$RAMANI_VERSION\")"
echo
echo "Ensure mavenLocal() is listed before mavenCentral() in the consuming project."
