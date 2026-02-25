import Foundation

/// Mirrors the accessibility identifiers used throughout the app.
/// Kept in the UI test target only — the app uses inline string literals.
enum AID {
    // MARK: - Onboarding
    static let welcomeContinue = "welcome_continue"
    static let conceptsContinue = "concepts_continue"
    static let permissionsContinue = "permissions_continue"
    static let analyticsEnable = "analytics_enable"
    static let analyticsDecline = "analytics_decline"
    static let thankyouContinue = "thankyou_continue"
    static let paywallSkip = "paywall_skip"
    static let onboardingBack = "onboarding_back"
    static let patternGrid = "pattern_grid"
    static let patternClear = "pattern_clear"
    static let patternStartOver = "pattern_start_over"
    static let recoverySaved = "recovery_saved"
    static let patternErrorMessage = "pattern_error_message"
    static let recoveryPicker = "recovery_picker"
    static let recoveryCustomPhraseInput = "recovery_custom_phrase_input"

    // MARK: - Pattern Lock (Unlock)
    static let unlockPatternGrid = "unlock_pattern_grid"
    static let unlockRecoveryLink = "unlock_recovery_link"
    static let unlockJoinLink = "unlock_join_link"
    static let unlockRecoveryPhraseInput = "unlock_recovery_phrase_input"
    static let unlockRecoveryError = "unlock_recovery_error"
    static let unlockRecoveryCancel = "unlock_recovery_cancel"

    // MARK: - Vault View
    static let vaultSettingsButton = "vault_settings_button"
    static let vaultLockButton = "vault_lock_button"
    static let vaultSelectAll = "vault_select_all"
    static let vaultEditDone = "vault_edit_done"
    static let vaultSearchField = "vault_search_field"
    static let vaultFilterMenu = "vault_filter_menu"
    static let vaultSelectButton = "vault_select_button"
    static let vaultEditDelete = "vault_edit_delete"
    static let vaultEditExport = "vault_edit_export"
    static let vaultAddButton = "vault_add_button"
    static let vaultAddCamera = "vault_add_camera"
    static let vaultAddLibrary = "vault_add_library"
    static let vaultAddFiles = "vault_add_files"
    static let vaultFirstFiles = "vault_first_files"
    static let vaultEmptyStateContainer = "vault_empty_state_container"

    // MARK: - Full Screen Viewer
    static let viewerDone = "viewer_done"
    static let viewerActions = "viewer_actions"

    // MARK: - Vault Settings
    static let vaultSettingsDone = "vault_settings_done"
    static let settingsChangePattern = "settings_change_pattern"
    static let settingsRegenPhrase = "settings_regen_phrase"
    static let settingsCustomPhrase = "settings_custom_phrase"
    static let settingsShareVault = "settings_share_vault"
    static let settingsDeleteVault = "settings_delete_vault"
    static let settingsAppSettings = "settings_app_settings"
    static let settingsDuressToggle = "settings_duress_toggle"

    // MARK: - App Settings
    static let appUpgrade = "app_upgrade"
    static let appAppearanceSetting = "app_appearance_setting"
    static let appPatternFeedback = "app_pattern_feedback"
    static let appAnalyticsToggle = "app_analytics_toggle"
    static let appIcloudBackup = "app_icloud_backup"
    static let appNuclearOption = "app_nuclear_option"
    static let debugResetOnboarding = "debug_reset_onboarding"
    static let debugFullReset = "debug_full_reset"

    // MARK: - Change Pattern
    static let changePatternTestSkipVerify = "change_pattern_test_skip_verify"
    static let changePatternErrorMessage = "change_pattern_error_message"

    // MARK: - Recovery Phrase View (Settings)
    static let recoveryPhraseSaved = "recovery_phrase_saved"

    // MARK: - Paywall
    static let paywallDismiss = "paywall_dismiss"

    // MARK: - Appearance modes (dynamic)
    static func appearanceMode(_ mode: String) -> String {
        "appearance_\(mode)"
    }
}
