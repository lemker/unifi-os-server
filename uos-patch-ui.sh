#!/bin/bash

# Make the UniFi OS row on the Updates page read-only, updating needs a new image
# Patterns change with each UniFi OS release, update them when the UI is left unpatched

UI_DIR="/usr/share/unifi-core/app/node_modules/@ubnt/unifi-portal/dist/local"
MARKER='if(w===T.o0.OS)return(0,s.jsx)(P.E,'

PATTERNS=(
    'let R=n,I=m[w]??C;'
    'function tl(e){let{row:t}=e,{original:n}=t;return(0,s.jsx)(e3,{...n})}'
    'function td(e){let{row:t}=e,{original:n}=t;return(0,s.jsx)(eF,{...n})}'
    'y=e=>{S.push(`${T}/${e.id}`)}'
    'f={id:"autoUpdateOn",accessorKey:"autoUpdateOn",header:g,'
    't=(0,s.jsx)(ev.tz,{...e,selectedAppId:r})'
)
REPLACEMENTS=(
    'let R=n,I=m[w]??C;if(w===T.o0.OS)return(0,s.jsx)(P.E,{variant:"body-primary",children:_.find(e=>e.id===I)?.label??I});'
    'function tl(e){let{row:t}=e,{original:n}=t;return n.id===T.o0.OS?null:(0,s.jsx)(e3,{...n})}'
    'function td(e){let{row:t}=e,{original:n}=t;return n.id===T.o0.OS?null:(0,s.jsx)(eF,{...n})}'
    'y="os"===C?void 0:e=>{S.push(`${T}/${e.id}`)}'
    'f={id:"autoUpdateOn",accessorKey:"autoUpdateOn",header:"os"===C?"":g,'
    't=(0,s.jsx)(ev.tz,{...e,...(e.id===T.o0.OS&&"action"===e.statusData?.variant&&{statusData:{...e.statusData,disabledReason:"Pull the latest container image to update."}}),selectedAppId:r})'
)

if grep -qF -- "$MARKER" "$UI_DIR"/main-*.js 2>/dev/null; then
    echo "UniFi OS update UI already patched"
    exit 0
fi

UI_FILE=$(grep -lF -- "${PATTERNS[0]}" "$UI_DIR"/main-*.js 2>/dev/null | head -1)
for pattern in "${PATTERNS[@]}"; do
    if [ -z "$UI_FILE" ] || [ "$(grep -oF -- "$pattern" "$UI_FILE" | wc -l)" -ne 1 ]; then
        echo "UniFi OS update UI pattern not found, leaving the UI unpatched" >&2
        exit 0
    fi
done

for i in "${!PATTERNS[@]}"; do
    FROM="${PATTERNS[$i]}" TO="${REPLACEMENTS[$i]}" perl -pi -e 's/\Q$ENV{FROM}\E/$ENV{TO}/' "$UI_FILE"
done

echo "UniFi OS update UI patched in $(basename "$UI_FILE")"
