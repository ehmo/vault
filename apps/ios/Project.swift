import ProjectDescription

// MARK: - Constants

let version = "1.0.2"
let buildNumber = "152"
let teamId = "UFV835UGV6"
let baseBundleId = "app.vaultaire.ios"

// MARK: - Embrace dSYM Upload Script

let embraceDSYMScript = """
# Upload dSYM files to Embrace for crash symbolication.
EMBRACE_ID=ehz4q
EMBRACE_TOKEN=9bba685da2e34a409e2d5059712a8da4
BUILD_DIR=${DWARF_DSYM_FOLDER_PATH}
if [ -d "$BUILD_DIR" ]; then
  for dsym in "$BUILD_DIR"/*.dSYM; do
    zip -r "${dsym}.zip" "$dsym" 2>/dev/null
    curl -s -X POST "https://symbols.embrace.io/upload" \\
      -F "app_id=$EMBRACE_ID" \\
      -F "token=$EMBRACE_TOKEN" \\
      -F "dsym=@${dsym}.zip" || echo "warning: Embrace dSYM upload failed for $dsym"
    rm -f "${dsym}.zip"
  done
else
  echo "warning: dSYM folder not found at $BUILD_DIR"
fi
"""

// MARK: - Shared Settings

let deploymentTargets: DeploymentTargets = .iOS("17.0")

let projectSettings: Settings = .settings(
    base: [
        "SWIFT_STRICT_CONCURRENCY": "complete",
        "DEVELOPMENT_TEAM": SettingValue(stringLiteral: teamId),
        "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES",
    ],
    configurations: [
        .debug(name: .debug),
        .release(name: .release),
    ]
)

// MARK: - Targets

let vaultTarget = Target.target(
    name: "Vault",
    destinations: .iOS,
    product: .app,
    bundleId: baseBundleId,
    deploymentTargets: deploymentTargets,
    infoPlist: .file(path: "Vault/Supporting/Info.plist"),
    sources: [
        .glob("Vault/App/**/*.swift"),
        .glob("Vault/Core/**/*.swift"),
        .glob("Vault/Features/**/*.swift"),
        .glob("Vault/Models/**/*.swift"),
        .glob("Vault/UI/**/*.swift"),
    ],
    resources: [
        "Vault/Resources/**",
    ],
    entitlements: .file(path: "Vault/Supporting/Vault.entitlements"),
    scripts: [
        .post(
            script: embraceDSYMScript,
            name: "Upload dSYMs to Embrace",
            inputPaths: [
                "${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Resources/DWARF/${TARGET_NAME}",
            ],
            basedOnDependencyAnalysis: false
        ),
    ],
    dependencies: [
        .target(name: "ShareExtension"),
        .external(name: "EmbraceIO"),
        .external(name: "TelemetryDeck"),
    ],
    settings: .settings(
        base: [
            "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
            "CURRENT_PROJECT_VERSION": SettingValue(stringLiteral: buildNumber),
            "MARKETING_VERSION": SettingValue(stringLiteral: version),
            "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
            "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
            "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
            "INFOPLIST_KEY_LSApplicationCategoryType": "public.app-category.utilities",
            "INFOPLIST_KEY_NSCameraUsageDescription": "Vaultaire needs camera access to capture photos directly into your secure vault.",
            "INFOPLIST_KEY_NSPhotoLibraryUsageDescription": "Vaultaire needs photo library access to import photos into your secure vault.",
        ],
        configurations: [
            .debug(
                name: .debug,
                settings: [
                    "CODE_SIGN_STYLE": "Automatic",
                    "CODE_SIGN_IDENTITY": "Apple Development",
                    "PROVISIONING_PROFILE_SPECIFIER": "",
                ]
            ),
            .release(
                name: .release,
                settings: [
                    "CODE_SIGN_STYLE": "Manual",
                    "CODE_SIGN_IDENTITY[sdk=iphoneos*]": "Apple Distribution",
                    "PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]": "Vault App Store",
                ]
            ),
        ]
    )
)

let shareExtensionTarget = Target.target(
    name: "ShareExtension",
    destinations: .iOS,
    product: .appExtension,
    bundleId: "\(baseBundleId).ShareExtension",
    deploymentTargets: deploymentTargets,
    infoPlist: .file(path: "Vault/Extensions/ShareExtension/Info.plist"),
    sources: [
        "Vault/Extensions/ShareExtension/ShareViewController.swift",
        "Vault/Extensions/ShareExtension/PatternInputView.swift",
        "Vault/Core/Crypto/CryptoEngine.swift",
        "Vault/Core/Crypto/SecureBytes.swift",
        "Vault/Core/Crypto/KeyTypes.swift",
        "Vault/Core/Crypto/KeyDerivation.swift",
        "Vault/Core/Crypto/PatternSerializer.swift",
        "Vault/Core/Security/SecureEnclaveManager.swift",
        "Vault/Core/VaultCoreConstants.swift",
        "Vault/Core/Storage/StagedImportManager.swift",
    ],
    entitlements: .file(path: "Vault/Extensions/ShareExtension/ShareExtension.entitlements"),
    dependencies: [],
    settings: .settings(
        base: [
            "CURRENT_PROJECT_VERSION": SettingValue(stringLiteral: buildNumber),
            "MARKETING_VERSION": SettingValue(stringLiteral: version),
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "EXTENSION $(inherited)",
            "SKIP_INSTALL": "YES",
            "INFOPLIST_KEY_CFBundleDisplayName": "Add to Vaultaire",
        ],
        configurations: [
            .debug(
                name: .debug,
                settings: [
                    "CODE_SIGN_STYLE": "Automatic",
                ]
            ),
            .release(
                name: .release,
                settings: [
                    "CODE_SIGN_STYLE": "Manual",
                    "CODE_SIGN_IDENTITY[sdk=iphoneos*]": "Apple Distribution",
                    "PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]": "ShareExtension App Store",
                ]
            ),
        ]
    )
)

let vaultTestsTarget = Target.target(
    name: "VaultTests",
    destinations: .iOS,
    product: .unitTests,
    bundleId: "\(baseBundleId).VaultTests",
    deploymentTargets: deploymentTargets,
    sources: [
        "VaultTests/**/*.swift",
    ],
    dependencies: [
        .target(name: "Vault"),
        .external(name: "ViewInspector"),
    ]
)

let vaultUITestsTarget = Target.target(
    name: "VaultUITests",
    destinations: .iOS,
    product: .uiTests,
    bundleId: "\(baseBundleId).VaultUITests",
    deploymentTargets: deploymentTargets,
    sources: [
        "VaultUITests/**/*.swift",
    ],
    dependencies: [
        .target(name: "Vault"),
    ]
)

// MARK: - Scheme

let vaultScheme = Scheme.scheme(
    name: "Vault",
    shared: true,
    buildAction: .buildAction(targets: ["Vault"]),
    testAction: .targets(
        [
            .testableTarget(target: "VaultTests"),
            .testableTarget(target: "VaultUITests"),
        ],
        configuration: .debug,
        diagnosticsOptions: .options(
            threadSanitizerEnabled: true,
            mainThreadCheckerEnabled: true
        )
    ),
    runAction: .runAction(
        configuration: .debug,
        executable: "Vault",
        options: .options(
            storeKitConfigurationPath: "Products.storekit"
        )
    ),
    archiveAction: .archiveAction(configuration: .release),
    profileAction: .profileAction(configuration: .release, executable: "Vault")
)

// MARK: - Project

let project = Project(
    name: "Vault",
    settings: projectSettings,
    targets: [
        vaultTarget,
        shareExtensionTarget,
        vaultTestsTarget,
        vaultUITestsTarget,
    ],
    schemes: [vaultScheme]
)
