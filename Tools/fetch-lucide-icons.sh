#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
app_dir=${script_dir:h}
destination="$app_dir/Sources/Nutrition/Resources/Lucide"
version="0.468.0"
icons=(archive calendar circle coins copy grip-vertical image image-plus leaf list-ordered map-pin pencil plus ruler save search settings star store trash-2 utensils x)

mkdir -p "$destination"
for icon in $icons; do
  curl --fail --location --silent --show-error \
    "https://raw.githubusercontent.com/lucide-icons/lucide/${version}/icons/${icon}.svg" \
    --output "$destination/${icon}.svg"
done

curl --fail --location --silent --show-error \
  "https://raw.githubusercontent.com/lucide-icons/lucide/${version}/icons/circle-check-big.svg" \
  --output "$destination/check-circle-2.svg"
curl --fail --location --silent --show-error \
  "https://raw.githubusercontent.com/lucide-icons/lucide/${version}/icons/utensils.svg" \
  --output "$destination/fork-knife.svg"

echo "Updated $((${#icons[@]} + 2)) Lucide icons from ${version}."
