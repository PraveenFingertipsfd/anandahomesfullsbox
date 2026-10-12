# Ananda Homes Salesforce Org — Technical Review

**Repo:** `anandahomesfullsbox`, branch `Praveen` @ `0d9034a` (2026-10-10)
**Default org:** `anandasbox` (drive-innovation-6570--anandasbox)
**Reviewer stance:** blunt, line-cited. Everything below was read from source or queried from the sandbox; items I could not execute are marked *(not executed)*.

---

## 0. Executive verdict

**Overall grade: D+.** There is real engineering talent in this codebase (the newer post-sales services and the config-driven approval/document/report engines are above average for a Salesforce services shop). It is wrapped in a process that cancels most of it out.

The five things a team leader needs to know, in order:

1. **The git repo is not the org, and the org is not the repo.** 182 of 300 Apex classes in git (the entire post-sales rebuild, dynamic approvals, dynamic forms, document engine, reports, dashboards) do not exist in `anandasbox`, and 31 custom objects they depend on (`Demands__c`, `NOC__c`, `Approval_Configuration__c`, …) are missing there too. Conversely, 138 classes in the org (mobile APIs, CP portal, `BulkRaiseDemandController`, `ReceiptController`, …) are not in git. None of the four other connected orgs holds the post-sales code either. All 37 flows in git are absent from the sandbox. **Nobody can currently say which org this repository describes.**
2. **Git HEAD does not compile.** `AgentDetailsAPI.cls:47` has an extra `}` introduced by today's merge commit `47ef1cb` ("Merge branch 'Praveen' into Tejshwini"). The org copy is fine. The next full deploy from this branch fails.
3. **The sandbox is in poor health.** Org-wide Apex coverage is **21%** (production needs 75%). A full `RunLocalTests` run I executed today: 1,055 methods, **154 failed, 3 classes fail to compile** ("Field is not writeable: Payment_schedule__c.Name"), 20 of 132 classes never completed. The last comparable run before mine was June 2026 (37 failures). Nobody is running the suite.
4. **The money path, as written in git, has several defects that would mis-state customer balances**: receipt allocation evaluates a Boolean that is never set (null → exception) *(not executed)*; the open-demand status filter uses two values that do not exist in the picklist; refund ceilings count pending and rejected receipts as cash; cloned bookings on unit swap get their payment schedules twice. Three BRD gates the code claims to enforce (receipt locking, one-pending-receipt, milestone sequencing) are commented out.
5. **Security is not enforced in code anywhere.** Across 137 production classes: 0 `WITH SECURITY_ENFORCED`, 0 `WITH USER_MODE`, 0 `stripInaccessible`. 29 classes are `without sharing`, 29 more have no sharing keyword at all. A live telephony API key and auth key are committed in `click2callController.cls:4-5`. At least 13 `Database.query` sites are injectable with client-supplied input. One VF controller mints public, password-less file links for any file Id it finds in rendered HTML.

Salesforce coding standards: **partially followed in the newest ~40 classes, not followed in the rest.** The project has a PMD ruleset that catches every category of violation present here. It has never been run.

---

## 1. Inventory

| Area | Count | Notes |
|---|---|---|
| Apex classes | 300 (137 prod, 163 test) | 30.6k prod LOC, 27.0k test LOC |
| Apex triggers | 21 | one per object in git; sandbox has 3 on standard `Lead` |
| Flows | 37 | 31 Active, 3 Draft, 3 Obsolete; 15 on `Booking__c` |
| LWC | 37 | 29.5k lines js+html; no Jest, no ESLint, no package.json |
| Aura | 19 | 9.9k lines; still actively authored (Click2Call added Sep 2026) |
| Visualforce | 47 pages | 22 hard-coded per-customer/per-bank PDF templates, ~20 Sites boilerplate |
| Custom objects | 69 `__c`, 4 `__mdt`, 1 `__e` | 2,285 fields; `Booking__c` alone has 388 |
| Custom metadata records | 244 | 227 country codes |
| Permission sets | 1 real | profiles not in source; access model unreproducible |
| API versions | classes 56–68, triggers 61–65 | `sfdx-project.json` says 62; governs nothing |
| Contributors | 2 humans + bot | Tejaswini 28 commits (two identities), Praveen 6, bot 16 |

**Business domain.** Real-estate CRM: pre-sales (Lead__c, Related_Source__c, Site_Visit__c, Follow_up__c, round-robin, channel partners, telephony), sales (Quote__c, Cost Sheet, Plot__c unit blocking), post-sales (Booking__c → Payment_Schedule__c → Demands__c → Receipt__c → Receipt_Line_Item__c, credit/debit notes, refunds, interest, NOC, swaps, cancellations), plus a set of metadata-driven engines (approvals, forms, documents, email, reports, dashboards, field mapping).

---

## 2. Source of truth: repo vs org (CRITICAL, process)

Evidence gathered from `anandasbox` today:

| Check | Result |
|---|---|
| Classes in git but not in org | **182** (all post-sales services, all Dynamic* / Approval* / Report* / Dashboard* / Email* / Document* engines, all their tests, `AgentDetailsAPI`, `HMACSignatureService`, …) |
| Classes in org but not in git | **138** (`All*API`, `CP*`, `*MobileAPI`, `BulkRaiseDemandController`, `ReceiptController`, `GenerateSaleDeed`, `ManualSharingClass`, `PaymentScheduleBatch`, `LeadTriggerHandlerStandard`, …) |
| Custom objects in git but not in org | **31** incl. `Demands__c`, `Advance_Payment__c`, `Payment_Schedule_Revision__c`, `NOC__c`, `First_Applicant_Change__c`, all 7 config objects |
| Flows in git present in org | **0 of 37** |
| Triggers | git has `ConstructionMilestoneTrigger`, `DemandTrigger`, `FirstApplicantChangeTrigger`, `NOCTrigger`, `PaymentScheduleRevisionTrigger`, `ReceiptLineItemTrigger` (not in org); org has `AdditionalChargeReceiptTrigger`, `AdditionalChargesTrigger`, `DemandRaisedTrigger`, `ChannelPartnerTrigger`, `LeadTriggerStandardLead`, `LeadTriggerHandlerStandard` (not in git) |
| `LeadTrigger` body | org (modified 2026-10-09) has an extra profile in the admin list and the Pre-Sales record-type assignment **commented out**; git has neither change. Deploying git would revert an org hotfix. |
| Other connected orgs (`orchid`, `orchidprod`, `mantri`, `jainshouse`) | none contain the post-sales classes |

What this means: the post-sales/config-framework code (roughly 60% of the repo by volume) was developed in some org that is not authenticated on this machine, or was authored locally and never deployed. The "chore: retrieve from DEFAULT" bot commits (16 of 50) overwrite git from an org whose identity is a GitHub secret. Commit `de54671` ("restore rebalanced ProrataInvariantServiceTest reverted by sandbox retrieve") and the deletion of `EmailSenderReceiptOwnerTest.cls` in retrieve `6f2da61` prove the bot has already destroyed hand-written code at least twice.

**The org is the master; git is a lossy backup of an unknown org.** Until this is fixed, every other finding in this document is a finding about a file, not about a system.

---

## 3. Triggers

21 triggers in git. One trigger per object is respected in git. The sandbox violates it with **three triggers on standard `Lead`** (`SLeadTrigger`, `LeadTriggerStandardLead`, `LeadTriggerHandlerStandard` — the last is a trigger *named like a handler class* with an empty body).

| Trigger | Pattern | Verdict |
|---|---|---|
| `LeadTrigger` (443 lines) | Logic inline, all 7 contexts, user SOQL at L10, 9 hard-coded profile names L19-21, ~200 lines commented out, swallowed DML L329/347, recursion guard `Utility.runLeadTrigger` checked at L4 but **never set false anywhere** | **F** |
| `RelatedSourceTrigger` (140 lines) | Logic inline; `@future` callout per insert; inserts `LeadShare` on standard Lead | D |
| `MasterPaymentScheduleTrigger` | SOQL inside `for (Trigger.new)` L17-21; disabled by label `Enable_Master_Payment_Schedule_Trigger = false` | D (and off) |
| `SiteVisitTrigger`, `BlockTrigger`, `UnitBlockHistoryTrigger` | Inline but bulk-safe | C |
| `ProjectTrigger` | 100% commented body | dead |
| `ReceiptTrigger` | Delegates; **before-insert/update gate calls commented out** L12-15 | C (BRD 5.12-5.15 off) |
| `ReceiptLineItemTrigger` | **Body fully commented** L8 | dead (BRD pointer 4 off) |
| `BookingTrigger`, `QuoteTrigger`, `UserTrigger`, `FollowUpTrigger`, `DemandTrigger`, `NOCTrigger`, `ConstructionMilestoneTrigger`, `PaymentSchedule*`, `FirstApplicantChangeTrigger`, `AdditionalChargeTrigger` | Thin trigger → service class, bulk-safe | B |

**Feature flags are Custom Labels** compared as strings with three different casings (`'TRUE'`, `'True'`, `'true'`). `Enable_Quote_Trigger` has zero references. The standard is a hierarchy Custom Setting or `__mdt` with a checkbox.

**Recursion control:** eight new services expose a `public static Boolean bypass` and callers save/restore it — correct. The legacy lead domain has none; re-entry paths exist via `RelatedSourceHandler:369`, `FollowUpHandler:81/105`, `SiteVisitTrigger:48`, `QuoteApprovalTriggerHandler:102`.

**Flow/trigger overlap:** `Booking__c` has a trigger plus 15 flows (11 active, 5 after-update with undefined order, 2 that update `$Record` in after-save and re-fire the stack). `Receipt__c`, `Demands__c`, `Lead__c`, `Follow_up__c` each have both a trigger and record-triggered flows with no documented ownership. **Zero fault connectors** across all 37 flows.

---

## 4. Apex classes — critical findings

Consolidated from four domain reviews; each item was read at the cited line. "Would fail" items marked *(not executed)* were traced, not run.

### 4.1 Compile / deploy blockers
- **`AgentDetailsAPI.cls:47`** — extra `}` from today's merge. Git HEAD will not deploy.
- Sandbox: `SaleAgreementControllerTest`, `RaiseDemandControllerTest`, `SwappingUnitControllerTest` fail to compile ("Field is not writeable: Payment_schedule__c.Name" — someone changed Name to auto-number without fixing tests).

### 4.2 Money integrity (post-sales, as written in git)
- **`FinancialTransactionController.cls:477-478, 543, 863, 883`** — `wrapper.useAdvances/useCredits` assignments are commented out; the fields are `null` Booleans evaluated in `if (wrapper.useAdvances && …)`. Apex throws `NullPointerException` on a null Boolean condition, `allocateReceipt` has no try/catch, so **every receipt approval would throw** *(not executed)*. The suite hides it: `FinancialTransactionControllerTest.cls:1486-1575` wraps every allocate call in `catch (Exception e) { /* ok */ }`.
- **`PostSalesConstants.cls:26-28`** — `DEMAND_OPEN_STATUSES = {'Open','Partial'}`; the `Demands__c.Status__c` picklist is `Raised | Emailed | Reminder Sent | Partially Paid | Paid | Overdue | Cancelled | On Hold | Termination Sent | Unit Unblocked`. `getOpenDemands` (L127) and `getOpenDemandsForAllocation` (L1111) can never return rows.
- **`FinancialTransactionController.cls:45-48, 1071-1088`** — refund ceiling derived from `Total_Receipt_Amount__c`, a roll-up with no status filter (counts Pending and Rejected receipts); refund inserted with `Status__c='Approved'` hard-coded.
- **`BookingSwapHandler.cls:181`** — `insert newBooking` fires `Booking_After_Create_Handler` (generates schedules + advance receipt), then the handler clones the old schedules/receipts on top. Duplicate schedules, phantom receipt.
- **`Credit_Note_Financial_Recalc.flow`** L43-94 — resets `Available_Amount__c = Credit_Amount__c` on every save of an Approved credit note; partially-applied credits re-inflate.
- **Two cancellation statuses.** Flow writes `'Cancelled'`; Apex everywhere uses `'Cancellation'` (`PostSalesConstants:41`, `BookingStageValidationService:66/75/81`, `InterestCalculationBatch:47`, `BulkDemandController:173…`). Flow-cancelled bookings keep accruing interest and reminders.
- **`DemandReminderService.cls:503-527`** — auto unit-unblock writes `Status__c='Cancellation'`, which `BookingStageValidationService` rejects; demand flags already committed with no savepoint → half-committed state, unit never released.
- `ReceiptAllocationService.cls:34-35` and `BookingFinancialRecalcService.cls:30` compare to literal `'Approved'`/`'Rejected'` while the picklist also contains `'Approved by Finance Team'` / `'Rejected by Finance Team'`.
- `BookingController.cls:364` — approval process name contains a literal **TAB**; `:408` submits to the wrong process (copy-paste).
- `BulkDemandController.cls:698-700` — trusts client-supplied `demandAmount`.
- `CreditNoteApplicationService` never reduces `Demands__c.Pending_Amount__c`; credit notes have no collection effect.
- Four different definitions of `Demands__c.Pending_Amount__c` across creators (`BookingFinancialRecalcService:217`, `PaymentScheduleViewController:378`, `BulkDemandController:690`, `ProrataDemandService:135` leaves it null).
- `NumberTOWordConvertion.cls:14-15` — `setScale(0)` rounds HALF_EVEN before splitting paise; amounts ≥ .50 print wrong words on customer documents *(not executed)*.

### 4.3 Security
- **`click2callController.cls:4-8`** — Knowlarity API key, auth key, DIDs committed. Rotate and move to Named Credential.
- **`CustomLookupGlobalController.cls:93-148`** — `@AuraEnabled`, `without sharing`, concatenates `query`, `objectName`, `filterField`, `searchString` raw. Any authenticated user can read any object.
- **`DynamicDocumentPDFController.cls:300-453`** — inner `without sharing` class inserts `ContentDistribution` (no password, no expiry, download allowed) for every 068/069 Id found in template JSON **or in rendered record HTML**. Anyone who can put a shepherd URL in a rich-text field gets a public link to any file in the org.
- **`DynamicFormExecutionController.cls:238-306`** — `saveFormWithChildren` inserts any object/fields the browser names; no `isCreateable`. Same shape at `DynamicApprovalController.cls:1009-1047` (update any field on any record).
- **`EmailSenderController.cls:253-330, 598, 623, 637, 691`** — client JSON drives WHERE clause, operator, ORDER BY direction, VF page to render, and recipients. Render-any-page-and-email-it primitive.
- **`ReportDataService.cls:6` / `DashboardDataService.cls:24,126`** — full config JSON accepted from client; visibility rules only applied in the list UI. `dateRange`/`number` filter values concatenated raw (`ReportDataService:960-970`).
- **`DynamicDocumentRenderer.cls:288, 436-439, 538, 890-896`** — record values into HTML unescaped, rendered with `escape="false"` → stored XSS on the VF domain.
- `LeadMergeController.cls:67-157` — merge + hard delete of any `Lead__c` by Id with no access check, 5 DML no savepoint. `LightningFileUploadHandler.cls:17-19` deletes any ContentDocument by Id in system mode.
- `GRE_Lead_Controller.cls:302`, `UserAvailabilityController.cls:25-43`, `UserStatusController.cls:13` — `update` on client-supplied sObjects in system mode (mass assignment).
- `SendLeadDetailsToPulseTeleSystem.cls:27` — hard-coded AWS endpoint, no auth, callout per record, all errors swallowed.
- `HMACSignatureService` and `PayloadMaskingService` are well-written and **unused**; `LeadPushAPI`/`LogPushAPI` rely on OAuth only.
- Repo-wide: **0** `WITH SECURITY_ENFORCED`, **0** `USER_MODE`, **0** `stripInaccessible`; 40 describe checks total, none on the arbitrary-object endpoints above. All 7 config objects are OWD Public Read/Write.

### 4.4 Correctness (pre-sales)
- **`RelatedSourceHandler.cls:152-169`** — duplicate check keys on `PhoneProject__c` / `Secondary_Phone_Project__c`, both **formula fields** (`IF(NOT(ISBLANK(Phone__c)),Phone__c,'')`). Formula fields are null on `Trigger.new` in before-insert, so `keySet` is empty and the method returns at L166. **Insert-time dedupe is a no-op** *(not executed; 2-minute anonymous Apex confirms)*. The re-open/re-engage flow depends on it.
- `GRE_Lead_Controller.cls:170-177` — writes a `Lead__c` Id into `SLead__c` (lookup to standard `Lead`) → DML type error.
- `pushToSalesController.cls:100,106` — filters `SLead__c` with a `Lead__c` Id → always empty → guards never fire.
- `RelatedSourceHandler.cls:3-6, 362-376` — class-static accumulators survive a failed DML; stale `deleteList` can delete unrelated leads on the next insert in the same transaction.
- `UnitBlockExpiryScheduler.cls:20-21` — only revokes blocks expiring *today*; one missed run leaves units Blocked forever.
- `HomeNotificationController.cls:26,34` — filters on `'Reschedule'`, `'Missed'`; picklist has neither. `LeadTrigger:150` branch on `'New'` is dead (not a picklist value). `'New sales enquiry'` vs `'New Sales Enquiry'` both written.
- `BulkReassignmenController` (674 lines, misspelled) — dead, targets standard Lead, undefined bind `:valuedate` L209, double `WHERE`.

### 4.5 Governor limits
- `InterestCalculationBatch` batch size 50 × 2–3 SOQL/booking (`:63-75`) → >100 SOQL per execute once ~34 bookings in a chunk have overdue schedules.
- `DemandReminderService.cls:576→779` — SOQL per e-mail inside 200-row loops, ×6 processors; PDF render per demand.
- `ReceiptAllocationService.cls:47` — `allocateReceipt` per receipt (~10 SOQL, ~6 DML each); `Receipt_Financial_Recalc` flow fires on every save with no change filter → ~24 SOQL per single approval.
- `ApprovalActionHandler` invocable: SOQL/DML/`sendEmail` per record per action.
- `DocumentViewerController.cls:135-140, 367, 470` — queries `Markup` of up to 1,000 ApexPages into heap; template JSON loaded twice per template.
- `DynamicApprovalService.hasField` (`:359-365`) → `Schema.getGlobalDescribe()` ~15× per submission.
- `SendLeadDetailsToPulseTeleSystem:30-62` — callout per record in a `@future`.

### 4.6 Standards scorecard

| Standard | Status | Evidence |
|---|---|---|
| Thin trigger / handler pattern | **Mixed** | 13 of 21 delegate; `LeadTrigger` 443 inline lines |
| One trigger per object | Git yes, **org no** | 3 triggers on `Lead` in sandbox |
| Bulkification | **Mixed** | New services good; 12 SOQL/DML-in-loop sites remain |
| Recursion control | **Partial** | 8 services with `bypass`; lead domain none; `runLeadTrigger` never set |
| Sharing declared | **No** | 29 `without`, 29 none, 0 `inherited` |
| CRUD/FLS enforced | **No** | 0 uses of any platform mechanism |
| SOQL injection safe | **No** | 13 injectable sites, 12 config-trust sites |
| No hard-coded IDs | **Mostly** | 1 record type Id in `Record_Type_Appartment` flow; profile/RT names by label everywhere |
| No secrets in code | **No** | `click2callController` |
| Exception handling | **Poor** | 186 `catch { /* ok */ }` in tests; dozens of `System.debug` catches in prod |
| No `System.debug` in prod | **No** | 278 in production classes |
| No `Test.isRunningTest()` in prod | **No** | 8 classes |
| Naming conventions | **Inconsistent** | lowercase classes (`followUpController`, `click2callController`…), PascalCase methods, misspellings (`BulkReassignmen`, `SimplyfyFilesCntrl`, `Intrest`, `Appartment`) |
| Dead/commented code | **Heavy** | ~600 lines commented in lead domain alone; 5 dead classes; 15 Sites `_Old` duplicates; `HelloWorld` scaffold |
| ApexDoc / authorship | **Boilerplate** | 40× `@author System`, 6× `@author Your Name`, "added by claude" ×6 |
| Decimal for money | **Yes** | no `Double` found |
| Custom labels for UI strings | **No** | 0 `@salesforce/label` imports in LWC |

---

## 5. Tests (grade D+)

**Git suite.** 163 test classes; **28 have zero asserts**; `System.assert(true)` ×19 in `DynamicApprovalControllerTest`, ×17 in `BookingControllerTest` (its only asserts). The flagship `FinancialTransactionControllerTest` is 1,712 lines, 76 methods, **6 asserts, 97 swallowing catches**. `FinancialTransactionControllerTest2` has 0 asserts and `return`s early when setup fails. `Test`/`Test2`/`Test3` split is explicitly for line-coverage chasing (headers say so). 15 classes use `SeeAllData=true` (all Sites boilerplate). Bulk (200-record) tests exist in 4 classes; `LeadTriggerTest` has none. 35 tests query `Profile WHERE Name = '…'` and 7 silently `return` if the profile is missing. `postSalesTestDataFactory` is used by ~17 classes; everywhere else a 40-line `Plot__c` block is copy-pasted. `click2callController` (does a callout) has no test.

Honest estimate: ~35-40% of test classes would catch a regression; the rest is coverage padding.

**Sandbox run (today, `RunLocalTests`, job `707HE00000KJOjg`):**

| Metric | Value |
|---|---|
| Org-wide coverage | **21%** |
| Methods enqueued / completed / failed | 1,055 / 927 / **154** (+3 compile failures) |
| Classes enqueued / completed | 132 / 112 |
| Top failure causes | `INVALID_OR_NULL_FOR_RESTRICTED_PICKLIST` ×73, `CANNOT_INSERT_UPDATE_ACTIVATE_ENTITY` ×30 (trigger errors inside test inserts), `STRING_TOO_LONG` ×16 |
| Worst classes | `AllSiteVisitAPITest` 28, `AnnouncementImageUploadControllerTest` 19, `ProjectDetailAPITest` 16, `BulkReassignmenController_Test` 13, `HomeDashboardAPITest` 12 |
| Lead-domain failures in classes that *are* in git | `SLeadTriggerHandlerTest` 3, `RelatedSourceHandlerTest` 2, `SLeadTriggerTest` 2, `LeadTriggerTest` 1, `followUpControllerTest` 1 |

The sandbox cannot be promoted to production in its current state.

---

## 6. Flows (grade D)

- 37 flows, **0 fault connectors**, including 19 Apex invocable calls and 7 DML elements.
- `Booking__c`: 15 flows (11 active). Five after-save update flows with undefined order. `Record_Type_Appartment` and `Update_booking_Stage` update `$Record` in after-save → re-fire the whole stack.
- **`Record_Type_Appartment`** sets `RecordTypeId = '0129I000001MJZhQAO'` (hard-coded, org-specific) on every new Booking with no criteria.
- Five flows have **no entry criteria** (`Lead_Assignment`, `Lead_Assignment_to_Sales_User`, `Follow_Ups_Assignment`, `Send_Demand_Email`, `Record_Type_Appartment`).
- `Send_Receipt_Email` fires on `Approval_Status__c = Approved` without `IsChanged` → likely re-sends on every edit.
- Three near-identical names (`Approval_Notification`, `Approval_Notification_Flow`, `Approval_Notifications_Flow`) on three objects; six flows share the label "Recalculate Booking Financials"; two labelled "Copy 1 of Send Notification"; one described as "Test".
- 3 Draft + 3 Obsolete flows committed. `Submit_For_Approval` targets an approval process not in source.

---

## 7. LWC / Aura (grade C)

- **No `package.json`, no ESLint, no Jest, no `__tests__`.** `.forceignore` excludes test/lint files that were never created.
- Monoliths: `documentDesigner.js` 1,567 lines, `formConfiguratorBuilder.js` 1,357, `financialTransactionManager.js` 1,315 (27 Apex imports, 4 transaction types, ~60 tracked fields), `GRE_LeadCreationController.js` 989.
- `@track` on primitives in 32/35 components (CI skeleton comment says it was removed).
- Swallowed errors: `bulkRaiseDemand.js:92,217,220`, `documentDesigner.js:998,1379-1398`, `financialTransactionManager.js:204-268` (8 loaders → empty tables, no toast), `dashboardConfigurator.js:322-326,870`.
- 87 `console.log` in 19 LWC files; `newLeadComponentController.js:96,106` logs the full lead payload (phone, email) to the browser console.
- 469 hard-coded UI strings, **0** `@salesforce/label`.
- `getEmailHistory` → `EmailSenderController.cls:943` sorts a wrapper that does not implement `Comparable`; its test catches the exception and passes.
- Aura is live, not legacy: `Click2Call` added 2026-09-03; 13 quick-action components whose QuickAction metadata is not in source; 6 Aura bundles have zero references.
- `helloWorld` LWC + `HelloWorld` class + test are CI scaffold shipped to a customer org, exposed in App Builder.

---

## 8. Metadata hygiene (grade D+)

- **Profiles, QuickActions, ApprovalProcesses, CustomApplications, CustomNotificationTypes, Named Credentials, Groups, Roles, Sharing Rules are not in source.** The repo cannot rebuild an org.
- Feature flags in Custom Labels (see §3). `Org_Wide_Address` label is a personal Gmail. `intergrationType` typo in an API name.
- Field typos propagated into code: `Intrest_Percentage__c`, `Intrest_Rate__c`, `Actual_Booking_Amout__c`, `Anniverssary_Date1__c`, `Avaliable__c`, `Unit_Type_Intrested__c`. 49 fields end in `1__c` (`Project__c`+`Project1__c`, `Booking_Amount__c`+`Booking_Amount1__c`, three Aadhaar fields).
- **Dual lead model**: standard `Lead` and `Lead__c` coexist; `SLead__c` (→Lead), `CLead__c` (→Lead__c), `New_Lead__c` (→Lead__c) all labelled "Lead" on `Booking__c`, `Follow_up__c`, `Quote__c`, `Site_Visit__c`. Three confirmed bugs above come from confusing them.
- 22 hard-coded Visualforce PDF templates (~8.7k lines), six named after **individual customers** (`ARJUN_SINGH_AGREEMENT_OF_SALE` …), 12 per-bank TPA pages, most with no controller, while a real `DynamicDocument*` engine exists alongside. `DocumentViewerController` glues them together by regex-scanning `ApexPage.Markup` at runtime.
- ~20 Sites/Communities boilerplate pages and 5 `_Old` controller triplets with no Site/Network metadata in source.
- `Drizzle_Logo.png` and `Prosper_Logo.png` are 70 bytes (broken).
- `Project_Name_Mappings__mdt` has zero records but is read by `Utility.getAllProjectNameMappings()`.

---

## 9. CI/CD and process (grade D)

- All three workflows are `workflow_dispatch` only. **Nothing runs on push or PR.**
- `03-deploy-to-salesforce.yml:6`: *"Just deploys. No scan, no validation, no tests."* `--test-level NoTestRun` at L362/378/395, including for the `PRODUCTION` target (Salesforce will reject it).
- `pmd-ruleset.xml` exists, is never executed, and lists exactly the rules this code violates (`AvoidSoqlInLoops`, `ApexCRUDViolation`, `ApexSOQLInjection`, `AvoidDebugStatements`, `ApexUnitTestClassShouldHaveAsserts`, `AvoidHardcodingId`, `EmptyCatchBlock`).
- Delta deploy diffs `HEAD~1..HEAD` (one commit), not since last deploy. Filename/`name:` are swapped between the 02 and 03 workflows. Salesforce CLI unpinned in deploy, pinned in retrieve.
- Retrieve bot defaults to committing straight to the current branch with `[skip ci]`; it has reverted human commits at least twice (see §2).
- `origin/main` has 6 commits, latest subject `"m"`; every working branch is 42-45 commits ahead. One PR ever merged (today). No CODEOWNERS, no PR template, no branch protection evidence.
- `README.md` is the unmodified skeleton ("my-sfdc-project"). `destructiveChanges.xml` is the empty template.
- Human commit messages are good (conventional, specific, reference QA items). That is the one bright spot.

---

## 10. What is done well

Credit where due; this is not a hopeless codebase.

- `BookingFinancialRecalcService`: idempotent full recompute with change detection and bypass. The right pattern, and it is why the triple flow-fire does not double-count.
- `PaymentScheduleRevisionService.stageAndSubmit`: trial `update` inside a savepoint to reuse trigger invariants as the single validator, then rollback. Clever and correct.
- `BookingSwapHandler`: generic clone with old→new Id registry, stale-reference fix-up, bypass restored in `finally`.
- `ProrataInvariantService` / `PaymentScheduleEditorController` share one invariant definition and say so.
- Static `bypass` flags saved and restored by every caller in the new services.
- `ApprovalActionHandler` / `ApprovalGenericStatusHandler`: per-action try/catch isolation, Chatter diagnostics so admins see why an action did not fire; describe-validated field names.
- `ReportDataService` / `DashboardDataService`: regex-whitelisted identifiers, whitelisted aggregations and operators (only the date/number branches slipped).
- `EmailSenderInvocable`: builds all messages, one `Messaging.sendEmail`.
- `LogPushAPI`: idempotent on `call_uuid`, consistent error helper, body truncated before logging. Best class in the lead domain.
- `BulkLeadReassignmentController` + `TempAssignmentExpiryBatch`: bulkified, audited, share removal scoped to the exact pair.
- `UnitBlockingController`, `UserAvailabilityHistoryHandler`, `NOCApprovalSyncService`, `BookingStageRemarkService`, `MilestoneStatusRemarkService`: clean, small, bulk-safe.
- `HMACSignatureService` (constant-time compare) and `PayloadMaskingService`: production quality, waiting to be wired in.
- Test classes `FinancialTransactionControllerTest3` (45 asserts), `DemandReminderServiceTest` (59), `ApprovalActionHandlerTest` (41), `BulkLeadReassignmentController_Test` (37), `LeadTriggerTest` (22) are real tests.
- Comments in the new code explain *why* (BRD sections, BUG ids, platform quirks). Most findings in this report were found because of them.

---

## 11. Grades

| Area | Grade |
|---|---|
| Source control / source of truth | **F** |
| CI/CD | D |
| Triggers | D |
| Pre-sales Apex (legacy core) | D |
| Post-sales Apex (new services) | C+ (B for design, D for the money defects) |
| Config-framework Apex | C (A for ambition, D for security) |
| Security (CRUD/FLS/injection/secrets) | **F** |
| Tests | D+ |
| Flows | D |
| LWC / Aura | C |
| Metadata hygiene | D+ |
| **Overall** | **D+** |

---

## 12. Recommended order of work

**This week (stop the bleeding)**
1. Fix `AgentDetailsAPI.cls:47`. Add a validate-only (`--dry-run`) deploy on every PR so this cannot recur.
2. Rotate the Knowlarity keys; move them to a Named Credential; purge from git history.
3. Decide the source of truth. Identify the "DEFAULT" org, retrieve *everything* from it into a fresh branch, diff against `anandasbox`, and write down which org owns which module. Disable the retrieve bot's commit-to-current-branch default.
4. Run anonymous Apex to confirm the `useAdvances` null and the formula-field dedupe; fix both; un-swallow the catches in `FinancialTransactionControllerTest`.
5. Fix `DEMAND_OPEN_STATUSES`, the `Cancelled`/`Cancellation` fork, and the refund roll-up filter.

**This month**
6. Enable PMD in CI with the existing ruleset; fail the build on `ApexSOQLInjection`, `ApexCRUDViolation`, `AvoidSoqlInLoops`, `ApexUnitTestClassShouldHaveAsserts`. Expect hundreds of hits; triage by severity.
7. Add `WITH USER_MODE` (or `stripInaccessible`) to every `@AuraEnabled` reader on the generic engines; add `isCreateable/isUpdateable` to the generic writers; fix the 13 injectable query sites.
8. Remove the public `ContentDistribution` minting; use `ContentVersion.VersionData` base64 only.
9. Refactor `LeadTrigger` into a handler; replace `Utility.runLeadTrigger` with a real guard; replace label flags with a `Trigger_Setting__mdt`.
10. Add fault paths to all 19 Apex-calling flows; delete the 6 Draft/Obsolete flows; consolidate the five after-update Booking flows and set `triggerOrder`.
11. Delete dead code: `BulkReassignmenController`, `Cost_SheetController`, `leadToSFController`, all `_Old` Sites classes/pages/tests, `HelloWorld*`, `ProjectTrigger`, `FormulaBuilderController`.

**This quarter**
12. Get the sandbox to green: fix the 3 compile failures, the 73 restricted-picklist failures, then raise coverage toward 75% with asserting tests. Add 200-record bulk tests for every trigger.
13. Bring profiles (or convert to permission sets), quick actions, approval processes and apps into source.
14. Add ESLint + Jest to LWC; remove `console.log`; move UI strings to labels.
15. Retire the 22 hard-coded VF PDF templates into `Document_Template__c`.
16. Reconcile the dual lead model (`SLead__c`/`CLead__c`/`New_Lead__c`) or at minimum document it and add a validation rule that one is populated.

---

*Method: 300 classes, 21 triggers, 37 flows, 37 LWC, 19 Aura, 47 VF pages and 74 object folders were read; four parallel domain reviews plus repo-wide static scans; live queries against `anandasbox` (class/trigger/object/flow inventory, `LeadTrigger` body diff, org-wide coverage, a full `RunLocalTests` run). No metadata was deployed and no org data was changed.*
