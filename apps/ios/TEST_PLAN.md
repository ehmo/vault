# Comprehensive Test Update Plan

## Overview
This document outlines the comprehensive test updates needed for the Vaultaire iOS app based on analysis of the codebase, scratch-pad learnings, and common mistakes.

## Current Test Coverage
- **30 unit test files** with ~376 tests
- **5 UI test files** with 11 tests
- **~7,042 lines** of test code

## Critical Testing Gaps (Priority Order)

### Phase 1: Critical Gaps (Immediate)

#### 1. VaultIndexManagerTests
**Location:** `VaultTests/VaultIndexManagerTests.swift`

**Test Cases:**
- [x] `testLoadIndex_CreatesNewVaultWithMasterKey()` - New vault auto-creates v3 index
- [x] `testLoadIndex_UsesCachedIndexForSameKey()` - Cache hit performance
- [x] `testLoadIndex_InvalidatesCacheForDifferentKey()` - Cache miss for different vault
- [x] `testLoadIndex_MigrationV1ToV2()` - Legacy v1 index migration
- [x] `testLoadIndex_MigrationV2ToV3()` - Legacy v2 index migration
- [x] `testLoadIndex_CorruptedDataThrows()` - Decryption failure handling
- [x] `testSaveIndex_UpdatesCache()` - Cache consistency after save
- [x] `testConcurrentIndexAccess()` - Thread safety with NSRecursiveLock
- [x] `testGetMasterKey_ThrowsWhenNil()` - Master key extraction error
- [x] `testInvalidateCache()` - Cache invalidation

**Common Mistakes to Catch:**
- Using bare `VaultIndex()` init instead of `loadIndex(with:)`
- Missing master key in v1 index creation
- Concurrent access without locking

#### 2. VaultViewModelTests
**Location:** `VaultTests/VaultViewModelTests.swift`

**Test Cases:**
- [ ] `testSearch_FiltersByFilename()` - Search functionality
- [ ] `testSearch_FiltersByMimeType()` - MIME type search
- [ ] `testSort_ByDateNewest()` - Date sorting
- [ ] `testSort_ByDateOldest()` - Reverse date sorting
- [ ] `testSort_ByName()` - Name sorting
- [ ] `testSort_BySize()` - Size sorting
- [ ] `testFileFilter_All()` - All files filter
- [ ] `testFileFilter_Media()` - Media-only filter
- [ ] `testBatchDelete_RemovesFiles()` - Batch deletion
- [ ] `testImportProgress_UpdatesCorrectly()` - Import progress tracking
- [ ] `testImport_Cancellation()` - Import task cancellation
- [ ] `testSearch_EmptyQueryShowsAll()` - Empty search behavior
- [ ] `testSearch_NoResultsShowsEmpty()` - No results handling

**Common Mistakes to Catch:**
- `@MainActor await` omission in import handlers
- Missing progress updates on MainActor before Task.detached
- Not handling all import error cases

#### 3. FileImporterTests
**Location:** `VaultTests/FileImporterTests.swift`

**Test Cases:**
- [ ] `testImportImage_CreatesThumbnail()` - Image import with thumbnail
- [ ] `testImportVideo_CreatesThumbnail()` - Video import with thumbnail
- [ ] `testImportDocument_NoThumbnail()` - Document import without thumbnail
- [ ] `testImportFromURL_StreamsLargeFiles()` - Streaming import
- [ ] `testImportData_SmallFile()` - Small file import
- [ ] `testImportData_LargeFileUsesStreaming()` - Large file streaming
- [ ] `testImport_Cancellation()` - Import cancellation handling
- [ ] `testImport_InvalidFileType()` - Invalid file handling
- [ ] `testImport_DiskFullError()` - Disk full error handling

**Common Mistakes to Catch:**
- Loading full file into memory for large files
- Not using streaming format for files > threshold
- Missing error handling for disk full

#### 4. CloudKitSharingManagerTests
**Location:** `VaultTests/CloudKitSharingManagerTests.swift`

**Test Cases:**
- [ ] `testSaveWithRetry_SucceedsOnFirstAttempt()` - Normal save
- [ ] `testSaveWithRetry_SucceedsOnRetry()` - Retry success
- [ ] `testSaveWithRetry_ExhaustsRetries()` - Retry exhaustion
- [ ] `testSaveWithRetry_RespectsRetryAfter()` - CKError.retryAfterSeconds
- [ ] `testUploadChunksParallel_BoundedConcurrency()` - Max 4 concurrent
- [ ] `testUploadChunksParallel_PropagatesErrors()` - Error propagation
- [ ] `testFetchOrCreatePattern_UpdatesExisting()` - CKError 14 handling
- [ ] `testFetchOrCreatePattern_CreatesNew()` - New record creation
- [ ] `testCheckPhraseAvailability_ReturnsCorrectStatus()` - Phrase validation

**Common Mistakes to Catch:**
- No retry on transient CloudKit errors
- Not using fetch-or-create pattern (CKError 14)
- Unbounded concurrency in chunk uploads
- Missing `await` on @MainActor singleton calls

#### 5. BackgroundTaskTests
**Location:** `VaultTests/BackgroundTaskTests.swift`

**Test Cases:**
- [ ] `testBeginBackgroundTask_CreatesTask()` - Task creation
- [ ] `testEndBackgroundTask_EndsTask()` - Proper cleanup
- [ ] `testBeginBackgroundTask_EndsPreviousTask()` - No orphaned tasks
- [ ] `testExpirationHandler_EndsTaskSynchronously()` - Synchronous cleanup
- [ ] `testUpload_WrappedInBackgroundTask()` - Upload backgrounding
- [ ] `testImport_WrappedInBackgroundTask()` - Import backgrounding

**Common Mistakes to Catch:**
- Orphaned background task IDs
- Async endBackgroundTask in defer
- Not wrapping long operations

### Phase 2: Feature Coverage (Short-term)

#### 6. SettingsViewTests
**Location:** `VaultTests/SettingsViewTests.swift`

**Test Cases:**
- [ ] `testSettings_NavigationToAppearance()` - Navigation flow
- [ ] `testSettings_NavigationToBackup()` - Backup settings
- [ ] `testSettings_VersionDisplay()` - Version number format
- [ ] `testSettings_PremiumStatus()` - Premium indicator

#### 7. PatternValidationTests
**Location:** `VaultTests/PatternValidationTests.swift`

**Test Cases:**
- [ ] `testValidationResult_MutuallyExclusiveWithError()` - State management
- [ ] `testInvalidPattern_ShowsFeedback()` - Invalid pattern UX
- [ ] `testValidPattern_TransitionsImmediately()` - No flash

**Common Mistakes to Catch:**
- Stale pattern feedback state
- Both validationResult and errorMessage set
- UI flash on valid pattern

#### 8. ErrorHandlingTests
**Location:** `VaultTests/ErrorHandlingTests.swift`

**Test Cases:**
- [ ] `testNetworkError_RetriesWithBackoff()` - Network retry
- [ ] `testDiskFullError_ShowsAlert()` - Disk full UX
- [ ] `testCorruptedDataError_Recovery()` - Corruption handling
- [ ] `testConcurrentModification_Handled()` - Race condition handling

### Phase 3: Edge Cases & Integration

#### 9. ImportProgressTests
**Location:** `VaultTests/ImportProgressTests.swift`

**Test Cases:**
- [ ] `testProgress_SetBeforeTaskDetached()` - Progress timing
- [ ] `testProgress_UpdatesOnMainActor()` - Thread safety
- [ ] `testStagedImport_UsesImportableCount()` - Accurate counts

**Common Mistakes to Catch:**
- Setting progress inside Task.detached
- Using raw manifest count instead of importable count

#### 10. KeyboardSafeAreaTests
**Location:** `VaultTests/KeyboardSafeAreaTests.swift`

**Test Cases:**
- [ ] `testJoinVaultView_IgnoresKeyboardSafeArea()` - Sheet keyboard
- [ ] `testRecoveryPhraseView_IgnoresKeyboardSafeArea()` - Sheet keyboard
- [ ] `testSharedVaultInviteView_IgnoresKeyboardSafeArea()` - Sheet keyboard

**Common Mistakes to Catch:**
- Missing `.ignoresSafeArea(.keyboard)` on sheets

## Test Infrastructure Improvements

### 1. Mock Improvements
- Create `MockCloudKitDatabase` for CloudKit testing
- Create `MockFileManager` for disk error injection
- Create `MockBackgroundTaskManager` for background task verification

### 2. Test Helpers
- `XCTestCase+Await.swift` - Async test helpers
- `XCTestCase+Assertions.swift` - Custom assertions for common patterns
- `TestDataFactory.swift` - Generate test files, vaults, etc.

### 3. Performance Tests
- `testStoreFile_Performance()` - Large file storage
- `testImportBatch_Performance()` - 200+ file import
- `testSearch_Performance()` - Search with many files

## Implementation Order

1. **VaultIndexManagerTests** - Foundation for other tests
2. **VaultViewModelTests** - Core functionality
3. **CloudKitSharingManagerTests** - Critical sharing logic
4. **BackgroundTaskTests** - Prevent regression
5. **FileImporterTests** - Import reliability
6. **PatternValidationTests** - UI state management
7. **ImportProgressTests** - Progress accuracy
8. **SettingsViewTests** - Settings coverage
9. **ErrorHandlingTests** - Error resilience
10. **KeyboardSafeAreaTests** - UI polish

## Success Criteria

- [ ] All new tests pass
- [ ] Existing tests continue to pass
- [ ] Code coverage increased by 20%+
- [ ] All common mistakes from scratch-pad have corresponding tests
- [ ] Tests run in CI without flakiness
