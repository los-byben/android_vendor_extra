enable_gms() {
    if [[ "${1:-false}" == "true" && -f vendor/pixel/gms/products/gms.mk ]]; then
        export WITH_GMS=true
        export TARGET_UNOFFICIAL_BUILD_ID=gms
        echo -e "\e[32m[INFO]\e[0m Enabling GMS build."
    else
        export WITH_GMS=false
        unset TARGET_UNOFFICIAL_BUILD_ID
        echo -e "\e[33m[WARN]\e[0m Building vanilla."
    fi
}

telegram() {
    local message="$1"
    ~/telegram.sh/telegram "$message"
}

apply_patches() {
    cd ${ANDROID_BUILD_TOP}
    PATCHES_PATH=$PWD/vendor/extra/patches
    for project_name in $(cd "${PATCHES_PATH}"; echo */); do
        project_path="$(tr _ / <<<$project_name)"
        cd ${ANDROID_BUILD_TOP}
        cd ${project_path}
        echo "Applying patches for project: ${project_name} on ${HEAD_COMMIT}"
        if ! git am "${PATCHES_PATH}"/${project_name}/*.patch --no-gpg-sign; then
            echo "Failed to apply patches for project: ${project_name}. Aborting."
            git am --abort &> /dev/null
        fi
        cd ${ANDROID_BUILD_TOP}
    done
}

_release_common() {
    device="$1"
    project="$(basename ${ANDROID_BUILD_TOP})"
    pr_branch="los-23"

    if [[ ${WITH_GMS} == "true" ]]; then
        type="GMS"
        device_variant="${device}_gms"
    else
        type="VANILLA"
        device_variant="${device}"
    fi

    echo -e "\e[32m[INFO]\e[0m Starting release for device: ${device} (${type} variant)"
    telegram "[INFO] Starting release for device: ${device} (${type} variant)"

    [[ -d "${ANDROID_BUILD_TOP}/ota" ]] && rm -rf "${ANDROID_BUILD_TOP}/ota"
    git clone git@github.com:los-byben/ota.git "${ANDROID_BUILD_TOP}/ota"
    cd "${ANDROID_BUILD_TOP}/ota"
    git pull origin "${pr_branch}"

    if git fetch origin "${pr_branch}"; then
        git checkout -B "${pr_branch}" origin/"${pr_branch}"
    else
        git checkout --orphan "${pr_branch}"
        git rm -rf ${device_variant}.json
    fi

    breakfast "${device}"
    m installclean

    if [[ -n "${extraimages}" ]]; then
        echo -e "\e[32m[INFO]\e[0m Running m bacon with extraimages for ${device}"
        m ${extraimages} bacon
    else
        echo -e "\e[32m[INFO]\e[0m Running m bacon for ${device}"
        m bacon
    fi

    get_prop() {
        local prop="$1"
        grep -h "^${prop}=" "${OUT}/system/build.prop" "${OUT}/product/etc/build.prop" 2>/dev/null | \
        head -1 | cut -d= -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
    }

    filename="lineage-$(get_prop 'ro.lineage.version').zip"
    tag_name=$(echo "$filename" | grep -oP '(?<=lineage-\d+\.\d+-)(\d{8})(?=-UNOFFICIAL)')

    if [ -z "$tag_name" ]; then
        tag_name=$(echo "$filename" | grep -oP '\d{8}(?=-UNOFFICIAL)')
    fi

    if [ -z "$tag_name" ]; then
        tag_name=$(echo "$filename" | grep -oP '(?<=lineage-\d+\.\d+-)(\d{8})')
    fi

    if [ -z "$tag_name" ]; then
        echo -e "\e[31m[ERROR]\e[0m Failed to extract tag_name (date) from filename: ${filename}"
        telegram "[ERROR] Failed to extract tag_name (date) from filename: ${filename}"
        exit 1
    fi

    metadata=$(unzip -p "${OUT}/${filename}" META-INF/com/android/metadata 2>/dev/null)

    get_meta() {
        local key="$1"
        grep -m1 "^${key}=" <<< "${metadata}" | cut -d= -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
    }

    sha256=$(awk '{print $1}' "${OUT}/${filename}.sha256sum")
    romtype=$(get_prop 'ro.lineage.releasetype')
    size=$(stat -c%s "${OUT}/${filename}")
    version=$(get_prop 'ro.lineage.build.version')
    datetime=$(get_prop 'ro.build.date.utc')
    os_patch_level=$(get_meta 'post-security-patch-level')
    os_sdk_level=$(get_meta 'post-sdk-level')
    ota_property_files=$(get_meta 'ota-property-files')

    if [ -z "${os_sdk_level}" ]; then
        echo -e "\e[31m[ERROR]\e[0m Failed to read post-sdk-level from ${filename} metadata."
        telegram "[ERROR] Failed to read post-sdk-level from ${filename} metadata."
        exit 1
    fi

    if [ -z "${ota_property_files}" ]; then
        echo -e "\e[33m[WARN]\e[0m ota-property-files missing from ${filename} metadata. Streaming updates will be unavailable."
    fi

    declare -gA image_map=(
        ["bootimage"]="${OUT}/boot.img"
        ["dtboimage"]="${OUT}/dtbo.img"
        ["initbootimage"]="${OUT}/init_boot.img"
        ["vendorbootimage"]="${OUT}/vendor_boot.img"
        ["recoveryimage"]="${OUT}/recovery.img"
    )

    extraimages=$(echo "${extraimages}" | xargs)
    echo "[INFO] Initial extraimages value: ${extraimages}"

    images=$(echo "${extraimages}" | grep -oP '\b\w*image\w*\b')
}

_release_finish() {
    if [ -z "${datetime}" ]; then
        echo -e "\e[31m[ERROR]\e[0m Failed to read ro.build.date.utc from ${filename}."
        telegram "[ERROR] Failed to read ro.build.date.utc from ${filename}."
        exit 1
    fi

    if [ -z "${size}" ]; then
        echo -e "\e[31m[ERROR]\e[0m Failed to determine file size for ${filename}. File may not exist."
        telegram "[ERROR] Failed to determine file size for ${filename}."
        exit 1
    fi

    ota_entry=$(jq -n \
        --argjson datetime "${datetime}" \
        --arg filename "${filename}" \
        --arg os_patch_level "${os_patch_level}" \
        --argjson os_sdk_level "${os_sdk_level}" \
        --arg ota_property_files "${ota_property_files}" \
        --arg sha256 "${sha256}" \
        --argjson size "${size}" \
        --arg romtype "${romtype}" \
        --arg version "${version}" \
        --arg release_url "$release_url" \
        '[
            {
                datetime: $datetime,
                files: [
                    {
                        filename: $filename,
                        os_patch_level: $os_patch_level,
                        os_sdk_level: $os_sdk_level,
                        ota_property_files: $ota_property_files,
                        sha256: $sha256,
                        size: $size,
                        url: $release_url
                    } | with_entries(select(.value != ""))
                ],
                type: $romtype,
                version: $version
            }
        ]')

    echo -e "\e[32m[INFO]\e[0m Generated OTA JSON entry:"
    echo "${ota_entry}"

    rm -f "${device_variant}.json"
    echo "${ota_entry}" > "${device_variant}.json"

    git add "${device_variant}.json"
    git commit --no-gpg-sign -m "${device_variant}: OTA update $(date +%F)"

    if [[ $(git rev-list --count HEAD) -gt 0 ]]; then
        pr_branch="ota-update-$(date +%Y%m%d%H%M%S)"
        git checkout -b "${pr_branch}"
        git push origin "${pr_branch}"
        pr_url=$(gh pr create --base los-23 --head "${pr_branch}" --title "OTA update for ${device_variant}" --body "This PR contains the OTA update for ${device_variant}." | grep -oP 'https://github.com[^\s]+')

        if [[ -n "${pr_url}" ]]; then
            echo -e "\e[32m[INFO]\e[0m PR created for ${device_variant}: $pr_url"
            telegram "[INFO] PR created for ${device_variant}: $pr_url"
        else
            echo -e "\e[31m[ERROR]\e[0m Failed to retrieve PR URL. PR creation may have failed."
            telegram "[ERROR] Failed to retrieve PR URL. PR creation may have failed."
        fi
    else
        echo -e "\e[31m[ERROR]\e[0m No commits found in ${pr_branch}. Aborting PR creation."
        telegram "[ERROR] No commits found in ${pr_branch}. Aborting PR creation."
        exit 1
    fi

    cd ..
    echo -e "\e[32m[INFO]\e[0m Deleting the OTA repo from ${ANDROID_BUILD_TOP}/ota."
    rm -rf "${ANDROID_BUILD_TOP}/ota"

    echo -e "\e[32m[INFO]\e[0m Release created successfully!"
    telegram "[INFO] Release created successfully for ${device_variant}."
}

release_gms() {
    local device="${1:?Usage: release_gms <device>}"
    enable_gms true
    extraimages="bootimage recoveryimage vendorbootimage initbootimage"
    sf_project_name="wakacaw-project"

    _release_common "${device}"

    release_url="https://sourceforge.net/projects/${sf_project_name}/files/${device}/lineage/${tag_name}/$(basename ${filename})/download"

    {
        echo "mkdir /home/frs/project/${sf_project_name}/${device}/lineage/"
        echo "mkdir /home/frs/project/${sf_project_name}/${device}/lineage/${tag_name}/"
    } | sftp ramaadni@frs.sourceforge.net

    rsync -Ph ${OUT}/${filename} ramaadni@frs.sourceforge.net:/home/frs/project/${sf_project_name}/${device}/lineage/"${tag_name}"/
    rsync -Ph ${OUT}/${filename}.sha256sum ramaadni@frs.sourceforge.net:/home/frs/project/${sf_project_name}/${device}/lineage/"${tag_name}"/

    echo "[INFO] Processing extra images (SourceForge):"
    echo "${images}"

    while IFS= read -r image; do
        if [[ -v "image_map[${image}]" ]]; then
            image_path="${image_map[${image}]}"
            if [ -f "${image_path}" ]; then
                remote_file="$(basename "${image_path}")"
                remote_path="/home/frs/project/${sf_project_name}/${device}/lineage/${tag_name}/${remote_file}"
                echo "[INFO] Checking size of ${remote_file} on the server at path: ${remote_path}"
                rsync_output=$(rsync --dry-run -avz "ramaadni@frs.sourceforge.net:${remote_path}" 2>&1)

                if echo "${rsync_output}" | grep -q 'No such file or directory'; then
                    echo "[INFO] ${remote_file} not found on the server. Proceeding with upload."
                    rsync -Ph "${image_path}" "ramaadni@frs.sourceforge.net:${remote_path}"
                else
                    remote_size=$(echo "${rsync_output}" | grep -oP '(\d+) bytes' | awk '{print $1}')
                    if [ -n "${remote_size}" ]; then
                        echo "[INFO] Found ${remote_file} on server, size: ${remote_size} bytes."
                        [ "${remote_size}" -gt 0 ] && echo "[INFO] ${remote_file} already exists. Skipping upload."
                    else
                        echo "[ERROR] Failed to extract size for ${remote_file}."
                    fi
                fi
            else
                echo "[ERROR] ${image_path} not found in ${OUT}"
            fi
        else
            echo "[ERROR] Unknown extra image: $image"
        fi
    done <<< "${images}"

    _release_finish
}

release_vanilla() {
    local device="${1:?Usage: release_vanilla <device>}"
    enable_gms false
    extraimages="bootimage recoveryimage vendorbootimage initbootimage"
    gh_repo="los-byben/ota"

    _release_common "${device}"

    gh_tag="${device}-${tag_name}"

    echo -e "\e[32m[INFO]\e[0m Vanilla build, uploading to GitHub Releases (${gh_repo})"

    gh_assets=("${OUT}/${filename}" "${OUT}/${filename}.sha256sum")

    echo "[INFO] Processing extra images (GitHub Releases):"
    echo "${images}"

    while IFS= read -r image; do
        if [[ -v "image_map[${image}]" ]]; then
            image_path="${image_map[${image}]}"
            [ -f "${image_path}" ] && gh_assets+=("${image_path}") \
                || echo "[ERROR] ${image_path} not found in ${OUT}"
        else
            echo "[ERROR] Unknown extra image: $image"
        fi
    done <<< "${images}"

    if gh release view "${gh_tag}" --repo "${gh_repo}" &>/dev/null; then
        echo "[INFO] Release ${gh_tag} already exists, uploading assets."
        gh release upload "${gh_tag}" "${gh_assets[@]}" --repo "${gh_repo}" --clobber
    else
        gh release create "${gh_tag}" "${gh_assets[@]}" \
            --repo "${gh_repo}" \
            --title "${device_variant} - ${tag_name}" \
            --notes "**Device:** ${device}
**Variant:** VANILLA
**Version:** ${version}"
    fi

    release_url="https://github.com/${gh_repo}/releases/download/${gh_tag}/$(basename ${filename})"

    _release_finish
}
