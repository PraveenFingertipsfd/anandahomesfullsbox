# Ananda Homes — Pre-Sales Flow Analysis

**Scope:** Lead__c and its related objects, Round Robin, Project / Block / Unit (Plot__c), Master Payment Schedule, Quote (cost sheet), and the hand-off into Booking__c.
**Sources:** repo `anandahomesfullsbox` branch `Praveen` @ `0d9034a`; live read-only queries against the default sandbox `anandasbox` on 2026-10-10. Line references are to files under `force-app/main/default/`. Items marked *(not executed)* were traced in code but not run.

---

## 0. Verdict

The pre-sales module is the oldest and most-used part of this org (832 leads, 870 enquiry logs, 144 site visits, 216 follow-ups in the sandbox). It works day to day because three Pre-Sales Executives and a handful of Associate Managers push leads through by hand. The automation around them is weaker than it looks:

1. **Duplicate detection does not run on insert.** The dedupe keys are formula fields that are empty in a before-insert trigger. Live proof: one phone number has 48 separate leads, all created by the API on 2026-09-02, all round-robined to different owners, none flagged. `Main_Lead__c` is populated on 0 of 832 leads, so the whole re-open / re-engage design is dormant.
2. **Round robin is fair but unguarded.** Assignment spreads evenly (240 / 236 / 224 leads across the three pre-sales executives). But the "available" flag is a preference, not a gate: the nightly job turns everyone off and the fallback pool assigns regardless. There is no locking, the fairness counter is shared across projects and pools, and seven orphan member rows have no parent queue.
3. **The lead status machine is not enforced anywhere.** `Lead_Status__c` is an unrestricted picklist, no validation rule or Apex checks transitions, and code writes a lower-case `New sales enquiry` that the UI checks never match. 87% of leads sit in `New Enquiry`, including 17 that already have follow-ups and 10 that already have site visits.
4. **The standard Lead object is dead weight.** Zero standard Lead rows exist, `SLead__c` is empty on every child record, yet four code paths still key on it, including three that silently do nothing and one that would fail (GRE site-visit creation).
5. **Inventory and scheduling are tiny and partly stuck.** Seven plots across three projects, all but one Blocked. 45 block-history rows are still `Blocked`, 6 of them past expiry, because **no scheduled Apex job exists in the sandbox**. The Drizzle project has no master payment schedule at all, so a Drizzle booking would generate zero payment milestones.
6. **The repo's post-sales booking automation does not match this org.** `Booking__c` here has `Stage__c` and no `Status__c`; `Master_Payment_Schedule__c` here lacks `Sequence__c`, `Payment_Type__c`, `Applicable_For__c`, `Days_After_Booking__c`, `Is_Agreement__c`. The git schedule generator and booking flows cannot run against this sandbox as-is.

---

## 1. Object model

```
Campaign__c ─┐                                   Channel_Partner__c ─┐
             ▼                                                       ▼
          Lead__c (RT: Pre_Sales | Sales | Associate*)  ◄── Main_Lead__c (self, re-open link; unused)
             │ CLead__c on every child (SLead__c → standard Lead is legacy, always null)
             ├──< Related_Source__c   (one row per enquiry touch: source, sub-source, campaign, CP, phones)
             ├──< Follow_up__c        (Scheduled → Pending → Completed/Cancelled)
             ├──< Site_Visit__c       (Scheduled/Rescheduled → Completed/Cancelled)
             ├──< Enquiry_Source__c   (legacy, reparented on merge only)
             ├──< Unit_Block_History__c ──> Plot__c
             ├──< Quote__c ──> Plot__c, Project__c ; ──< Cost_Sheet_Line_Item__c ──> Master_Payment_Schedule__c
             └──< Booking__c ──> Quote__c, Plot__c, Project__c

Round_Robin__c (one per project, Project_Assigned__c picklist) ──< Round_Robin_Member__c ──> User
   fairness pointer lives on User.LastAssignmentTime1__c / LastSVAssignmentTime__c (not in source)

Project__c ──< Block__c (tower) ──< Plot__c (unit, master-detail to Project__c)
Project__c ──< Master_Payment_Schedule__c (milestone template, % of cost)
```
\* `Associate` record type exists in the sandbox (25 leads) but not in git.

| Object | Fields | Record types | VRs | Role | Key automation |
|---|---|---|---|---|---|
| Lead__c | 239 | Pre_Sales, Sales (+Associate in org) | 1 (10-digit phone) | The enquiry | LeadTrigger (443 lines inline), RelatedSourceHandler, RoundRobinHandler, flows Lead_Assignment, Lead_Assignment_to_Sales_User |
| Related_Source__c | 60 | — | 0 | Enquiry log per touch | RelatedSourceTrigger (telephony callout; dead CP-share logic) |
| Follow_up__c | 24 | — | 9 | Calls / tasks | FollowUpTrigger, 2 flows with scheduled paths |
| Site_Visit__c | 53 | 1 | 8 (4 inactive) | Visits | SiteVisitTrigger, Site_Visit_Scheduled_Notification flow |
| Round_Robin__c / Member | 2 / 8 | — | 0 | Per-project queues | RoundRobinHandler; RoundRobinUsersView toggles |
| Project__c | 106 | — | 0 | Master project, role lookups, roll-ups of unit counts | ProjectTrigger (100% commented) |
| Block__c | 16 | — | 2 | Tower | BlockTrigger (interest cascade) |
| Plot__c | 145 | — | 0 | Unit and price list, `Status__c` NOT RELEASE FOR SALE / Available / Blocked / Booked / Sold | UnitBlockingController, QuoteApprovalTriggerHandler, UnitBlockHistoryTrigger, BookingController |
| Unit_Block_History__c | 14 | — | 1 | Hold audit, Blocked / Revoked / Converted | UnitBlockExpiryScheduler (not scheduled) |
| Master_Payment_Schedule__c | 33 in git, 20 in org | — | 1 | Milestone template | MasterPaymentScheduleTrigger (disabled by label) |
| Quote__c | 84 | — | 0 | Cost sheet | QuoteTrigger → approval routing + unit block; Cost_Sheet_Notification flow |
| Cost_Sheet_Line_Item__c | 48 | — | 0 | Payment plan on the quote | — |
| Booking__c | 388 | Apartment, Plot, Villa | 14 | Conversion target | 15 flows + BookingTrigger (post-sales) |

**Three identities for "project".** `Project__c` lookup Id (Plot, Block, MPS, Quote.Project1__c), the `Project_Name` global picklist text (Lead.Allocated_Project__c, Round_Robin.Project_Assigned__c, Quote.Project__c, Unit_Block_History.Project__c), and `Project__c.Name`. Code mixes all three: `CreateQuoteController.cls:49,130` filters on `Project__r.Name`, `UnitBlockingController.cls:38,50` on the picklist and `:95` on Name, `QuoteApprovalTriggerHandler.cls:218-233` writes `Project__c.Name` into a restricted picklist. It only works while every project's Name equals its picklist label.

**Three lookups for "lead".** `SLead__c` → standard Lead, `CLead__c` → Lead__c, `New_Lead__c` → Lead__c, all labelled "Lead" on Booking, Follow-up, Quote, Site Visit, Related Source. In the sandbox: standard Lead count 0; `SLead__c` populated on 0 rows of every object; `New_Lead__c` populated on 0 follow-ups.

---

## 2. Sandbox snapshot (2026-10-10, read-only)

| Measure | Value |
|---|---|
| Lead__c total | 832 (Pre Sales 738, Sales 69, Associate 25) |
| By status | New Enquiry 724 · Site Visit Scheduled 29 · Cost Sheet Preparation 21 · Site Visit Completed 16 · New Sales Enquiry 14 · Pre Sales Follow Up 8 · Unqualified 6 · Closed Lost 4 · Booked 2 · other 8 |
| By Lead_Type__c | New Lead 802 · Re-Engaged 26 · Re-Opened 4 |
| Created by | API integration user 633 · System Administrator 98 · LogPush API 39 · LeadPush API 42 · humans 20 |
| Owners | Pattu 240 · Sandeep 236 · Haresh 224 (Pre-Sales Executives) · Admin 39 · Associate Managers 97 |
| `Lead_source__c` populated | 2 of 832 (both Walk-in). `Primary_Source__c` is the real source: Digital 447, Walk-in 172, Referral 74, CP 48, Organic 40 |
| Leads created, last 90 days | Jul 8 · Aug 175 · Sep 441 · Oct 129 |
| Duplicate phones | top 10 phones account for 253 leads; 9663368511 has 48 (all "SAI KRISHNA BATTULA", API, 2026-09-02) |
| `Main_Lead__c` set | 0 of 832 · `Delete_Lead__c` true: 0 |
| Unassigned (`Lead_Assigned__c=false`) | 32, of which 31 sit with the admin user |
| Related_Source__c | 870 (New Lead 814, Re-Engaged 49, Re-Opened 7); CLead__c 870, SLead__c 0; 5 leads have 5–8 enquiry rows |
| Site_Visit__c | 144: Completed 70, Scheduled 48, Cancelled 24, Rescheduled 2 |
| Follow_up__c | 216: Pending 133, Cancelled 36, Completed 32, Missed 15 |
| Status drift | 17 `New Enquiry` leads already have follow-ups; 10 already have site visits; 3 have `Site_Visit_Done__c = Yes` |
| Round robins | RR-0003 Ozone Heights (3 Pre Sales + 4 Sales), RR-0004 Legacey (3 Pre Sales + 2 Sales + 1 CRM unavailable), RR-0005 Drizzle (3 Pre Sales + 5 Sales, 3 inactive), RR-0006 inactive; **7 member rows with no parent queue**; `Last_Assigned_Time__c` null on every member |
| Users | 29 active; 15 available+working, 2 working but unavailable, 12 neither |
| Projects | The Drizzle (Apartments, 2 units), The Legacey (Commercial, 4 units), The Ozone Heights (Apartments, 2 units); `Interest_Percentage__c` blank on all |
| Plots by status | Drizzle: 1 Available, 1 Blocked · Legacey: 4 Blocked · Ozone: 2 Blocked |
| Unit_Block_History__c | Blocked 45 · Revoked 8 · Converted 1; **6 Blocked rows have expiry in the past**; 2 Blocked rows whose plot is not Blocked; quote-created blocks have no expiry date |
| Master_Payment_Schedule__c | Legacey 17 lines = 100% (one stray 1% line with no serial number); Ozone 1 line = 100%; **Drizzle: none** |
| Quote__c | 45, all with unit and project, 33 with manager; statuses Approved 15, Rejected 14, Submitted 8, Accepted by Customer 5, Denied by Customer 3 |
| Booking__c | 2, both `Stage__c = New Booking`, both linked via CLead__c and Quote__c |
| Scheduled Apex jobs | **0** (no unit-block expiry, no nightly availability reset, no temp-assignment expiry) |
| Org-wide Apex coverage | 21% |

---

## 3. Process map

### 3.1 Entry channels (every path runs the full LeadTrigger)

| # | Channel | Code | Sets | Notes |
|---|---|---|---|---|
| 1 | New Lead quick action (Aura `newLeadComponent`) | `lightning:recordEditForm`, helper Apex `transferLeadController` | Name, project, phone(s), emails, Medium, Source_Type, Primary_Source / Sub_Source, CP, budget, property type | `Lead_source__c` not on the form → always Pre Sales RT. The inline duplicate pre-check calls `checkPhoneNumberExistence` / `checkEmailExistence` which do not exist in Apex (`newLeadComponentController.js:257,319`), so the warning never fires. |
| 2 | GRE walk-in desk (Aura `GRE_LeadCreation`, 989-line controller) | `GRE_Lead_Controller` | Forces `Lead_source__c='Walk-in'`, `Round_Robin_Off__c=true`, `Lead_Assigned__c=false`, `Pushed_On/By` (`GRE_LeadCreationController.js:106-141`) | Created as Sales RT owned by the GRE user, then a second server call re-assigns via `assignSingleLead` and auto-creates a Completed site visit (`GRE_Lead_Controller.cls:408-444`). Two owner-change notifications per lead. |
| 3 | REST `POST /services/apexrest/LeadPush` | `LeadPushAPI.cls` | Names, phones, emails, Primary_Source / Sub_Source, project, property type, BHK, budget, remarks, `Lead_Status__c='New Enquiry'`, campaign text; logs to `Apex_Log__c` | Source of 633+ of the 832 leads and of all 48 duplicates. Returns the new Id even if the trigger later deletes it as a duplicate (`:104-109`). |
| 4 | Standard Lead → Lead__c bridge | `SLeadTrigger` → `SLeadTriggerHandler.pushToCustomLead`, then `@future` delete of the standard Lead | 10 mapped fields; `Primary_Source__c` and status not mapped | Feeder is `leadToSFController` (dead VF page) or web-to-lead (not verified). Zero standard Leads in the org today. |
| 5 | Data Loader / bulk | any insert | whatever the file has | Intra-batch duplicates both survive (`RelatedSourceHandler.cls:572,586` commented). |
| 6 | Transfer lead to another project | `transferLeadController.moveToSales` | — | Fully commented out (`:76-112`). Dead feature. |

### 3.2 Before insert (`LeadTrigger.trigger`)

Gate: label `Enable_Trigger == 'TRUE'` and `Utility.runLeadTrigger` (never set false anywhere, so re-entry from the after-insert self-update is uncontrolled).

| Step | Line | Effect |
|---|---|---|
| 0 | `:10` | SOQL for the running user's profile |
| 1 | `:11` → `RelatedSourceHandler.checkMobileNumber:11-67` | If phone starts with `+`: strip, detect `91` else first matching country code by unordered map iteration; default India. A phone like `919876543210` without `+` is not stripped and fails the 10-digit validation rule. |
| 2 | `:12` → `mapCampaignLookup:591-634` | Resolve `Campaign__c` text to `Campaign_Name__c` lookup (Id or name match). |
| 3 | `:13` → `duplicateCheck2:152-223` | **No-op on insert.** Keys are `PhoneProject__c` / `Secondary_Phone_Project__c`, formula fields (`IF(NOT(ISBLANK(Phone__c)),Phone__c,'')`), which are null on `Trigger.new` before insert, so `keySet` is empty and the method returns at `:166`. The older working version keyed on `Phone__c` is commented at `:70-148`. Even when it worked the key was phone only; e-mail dedupe never existed. |
| 4 | `:19-21` | Nine hard-coded "round-robin" profiles. Of them only System Administrator, LeadPush Profile and Minimum Access - API Only Integrations exist among active users. The `GRE` profile (3 users) is not listed, so GRE leads self-assign and rely on the controller's own RR call. |
| 5a | RR profile `:23-43` | `Lead_source__c=='Walk-in'` → Sales RT + `'New sales enquiry'` (lower case, not the picklist value), RR only if not `Round_Robin_Off__c`. Else → Pre Sales RT, RR unconditionally (`Round_Robin_Off__c` ignored for Pre Sales). |
| 5b | non-RR profile `:45-53` | `Lead_Assigned__c=true`, owner = creator. |

Before update (`:134-199`): phone-change dedupe reads the stale formula so it only ever finds the record itself; the `'New'` branch at `:150` is dead (not a picklist value); the `'New sales enquiry' && pushToSalesController.pushToSales && !Lead_Assigned__c` branch at `:152` re-runs Sales RR on any edit because `pushToSales` is a static defaulting to true.

Before delete (`:200-222`): blocks delete when Site Visits, Quotes, Follow-ups or Bookings exist. Related Sources are not checked.

### 3.3 Round Robin engine (`RoundRobinHandler.cls`)

**Model.** One `Round_Robin__c` per project (`Project_Assigned__c` picklist, `Active__c`). Members carry `User__c`, `User_Type__c` {Pre Sales, Sales, CRM}, `Active__c`. The member fields `Avaliable__c` and `Last_Assigned_Time__c` are unused (null on every row in the org). The fairness pointer is `User.LastAssignmentTime1__c` (epoch millis) and `User.LastSVAssignmentTime__c`, surfaced through formula fields on the member. User fields are not in source.

**`assignLead(leads, updateLeads, usType)` (`:2-113`)**
1. Day of week from `now.format('EEEE')` in the running user's locale.
2. Group leads by `Allocated_Project__c`; skip `Lead_Assigned__c`, `Delete_Lead__c`, blank project.
3. Two queries: *available* = member Active, `User.Availability__c`, `IsActive`, `is_working__c`, `Week_off_days__c` excludes today, matching type, ordered by last-assignment time ascending; *fallback* = same without `Availability__c`.
4. Per project: available list if non-empty else fallback; deal leads round the list starting at the least-recently-assigned member.
5. Writes `OwnerId`, `Lead_Assigned__c=true`, `Pre_sales_user__c` (Pre Sales) or `Sales_User__c` + `SV_User__c` (Sales). `SV_User__c` is set only in the available branch (`:58` vs `:84-88`).
6. One update of `User.LastAssignmentTime1__c` for the members used.

**Availability.** `Availability__c` is self-toggled (`UserStatusController`, with a reason captured to `User_Availability_History__c`); `is_working__c` is admin-set (`UserAvailabilityController`). `UserAvailabilityOffScheduler` sets `Availability__c=false` for every active user nightly, so until people toggle on each morning the available list is empty and **every lead goes through the fallback list**. In the sandbox the scheduler is not scheduled, and 15 users show available; the behaviour is therefore untested here.

**Single-lead variants** `assignSingleLead` / `assignSingleSiteVisit` (`:116-203`) are used by GRE; the second keeps a separate fairness counter for who handles the visit.

**Defects.**
- No `FOR UPDATE`; two concurrent inserts for one project read the same order and both pick member 0.
- The fairness counter is per user across all projects and both pools: assignment in one queue pushes the user to the back of every queue.
- No member → lead silently keeps the integration user as owner with `Lead_Assigned__c=false`, and the `Lead_Assignment` flow still sends "assigned to you" to that integration user. 31 such leads sit with the admin today.
- `RoundRobinUsersView` lets anyone with record access toggle `Active__c` with no audit.
- Seven member rows have no parent queue (data hygiene).
- `RR-0004` has a CRM member who is unavailable; CRM type is never requested by code.

### 3.4 After insert (`RelatedSourceHandler.afterinsertLogic2`)

- New lead → one `Related_Source__c` (`Lead_Type__c` defaults to New Lead) copying source, sub-source, medium, CP, campaign, phones, emails, project; plus a self-update stamping `First/Last_Source_Of_Enquiry__c = Lead_source__c` (null for API leads), `First_Contatced_On__c`, campaign and CP primaries (`:286-358`). The self-update re-enters LeadTrigger.
- Duplicate (`Delete_Lead__c && Main_Lead__c`) → `addRelatedSource` (`:379-519`): attach the enquiry to the main lead, `Re-Opened` if main is Unqualified/Closed Lost (resets status, RT, 20+ fields, owner unchanged), else `Re-Engaged`; delete the new lead. **Unreachable from the trigger** because step 3 never sets the flags; the 26 Re-Engaged and 4 Re-Opened leads in the org came from the GRE path or manual data.
- `RelatedSourceTrigger`: `@future` POST per Related Source to the Pulse telephony endpoint (`SendLeadDetailsToPulseTeleSystem.cls:27`, hard-coded AWS URL, no auth, errors swallowed), fired for every enquiry row including re-engagements. The CP re-engage date and `LeadShare` logic (`:37-80, 94-138`) keys on `SLead__c` and never runs for Lead__c; channel partners get no record access.
- Flow `Lead_Assignment` (after create, no criteria): custom notification to `OwnerId`.
- CP expiry (`LeadTrigger.trigger:272-298, 370-437`): computes a CP-owner map on owner change within `CP_Lead_Expiry_Days` (90) and then does nothing; the sharing block is commented.

### 3.5 Working the lead

**Follow-ups.** Created together with a site visit from `newSiteVisitComponent` (`followUpController.createFollowUpApex:26-75`, adds a hard-coded +5h30 to the date). `FollowUpHandler.validateSingleScheduledFollowup` allows one Scheduled follow-up per lead **per owner**. After insert, `Next_Followup_Date__c` / `Recent_Followup_Date__c` are stamped on the lead. Flow `Followup_Pending_Status_Update_and_Notification` moves Scheduled → Pending 15 minutes after the date and notifies the owner; flow `Follow_Ups_Assignment` reminds **`CreatedById`**, not the owner, 5 minutes before. 133 of 216 follow-ups are Pending, which is where this design parks everything that is not closed on time.

**Site visits.** Created by `followUpController.createSiteVisitApex:102-150` (owner = lead owner, +5h30) or by GRE (`saveChanges` upserts a Completed visit with `Handled_By__c` from the SV round robin). `SiteVisitTrigger` stamps `SV_Completed_Date_Time__c` and sets `Lead.Site_Visit_Done__c='Yes'` (never reset). GRE's "Complete" button writes `GRE Verified`, a value not in the picklist, so the completion trigger does not fire for that path (`GRE_Lead_Controller.cls:212`). The reminder flow fires only when `Owner_Changed__c=true`, which only push-to-sales sets, so normally scheduled visits get no reminder.

**Lead status.** Unrestricted picklist, 14 values, no transition guard anywhere. Code sets only: `New Enquiry` (API, re-open), `New sales enquiry` lower-case (walk-in, push), `New Sales Enquiry` proper-case (re-open from Closed Lost), `Site Visit Scheduled` (push, site-visit component), `Site Visit Completed` (GRE), `Unqualified` / `Closed Lost` (status quick action), `Booked` (BookingController). `Cost Sheet Preparation`, `Pre Sales RNR`, `Pre Sales Follow Up`, `Sales RNR`, `Prospect` values are manual only. Lost/won cascades in `LeadTrigger.trigger:284-351` cancel Scheduled site visits (with a trailing tab in the reason text at `:325`) and Scheduled/Pending follow-ups; errors are swallowed to `System.debug`.

**Agenda** (`HomeNotificationController`): filters site visits on `'Reschedule'` and `'Missed'`, neither of which is a picklist value (`:26,34`); "pending follow-ups" looks for yesterday's Scheduled rows, which the flow has already moved to Pending.

### 3.6 Pre-Sales → Sales hand-off

**`pushToSalesController.moveToSales` (`:5-97`):** stamps `Pre_sales_user__c`, `Old_Owner_Name__c`, switches RT to Sales, clears `Lead_Assigned__c` (or sets the chosen sales user), writes `'New sales enquiry'`, `Pushed_On/By`, `IsPushed__c`; the update triggers Sales RR in the before-update branch; then shares the lead Read to the pre-sales user (`Lead__Share`, OWD is Private), re-owns follow-ups and Scheduled site visits to the sales owner with read shares back. Flow `Lead_Assignment_to_Sales_User` notifies the new owner. The guards `CheckFollowups` / `isSiteVisitScheduled` filter `SLead__c` with a Lead__c Id and always return empty (`:100,106`).

**GRE hand-off** (`GRE_Lead_Controller.saveChanges:270-387`): record type, owner, status, `Lead_Type__c` all set client-side and saved with a blind `update ldRec` (`:302`). Bypasses `pushToSalesController`: no `IsPushed__c`, follow-ups and visits not re-owned, old follow-ups left for a pre-sales owner who can no longer create new ones (validation rule `Block_Create_For_Pre_Sales_On_Sales_Lead`). `createSiteVisit:170-177` writes a Lead__c Id into `SLead__c` (lookup to standard Lead) and would fail *(not executed)*.

**Bulk reassignment** (`BulkLeadReassignmentController`): permanent moves the owner only (children, `Pre_sales_user__c`, `Sales_User__c` untouched); temporary adds `Temp_Owner__c` and Manual edit shares on lead, follow-ups, visits, logs `Reassignment_History__c`; expiry batch deletes every Manual share for that user, including the pre-sales Read share created by push-to-sales. The expiry batch is not scheduled in the sandbox.

**Merge** (`LeadMergeController`): reparents Enquiry Sources, follow-ups, visits, related sources, deletes the duplicate. Leaves Quotes, Bookings and block histories on the duplicate; no savepoint, so the before-delete guard can throw after children were moved.

### 3.7 Project, inventory, master schedule

- **Project__c** carries the role lookups copied onto bookings, `Booking_Advance_Amount__c`, `Max_Unit_Block_Days__c`, roll-ups of unit counts. `Enable_Auto_Unit_Unblocking__c` and its day fields are read by nothing. `ProjectTrigger` is 100% commented, so changing `Interest_Percentage__c` does nothing; `BlockTrigger` does cascade `Intrest_Percentage__c` (typo) to payment schedules.
- **Plot__c** is master-detail to Project, lookup to Block. ~90 pricing fields, many duplicated (`Basic_Cost__c`, `Basic_Cost1__c`, `Basic_Price__c`, `Basic_Price45__c`, `Basic_Prices1__c`, `Basic_Sale_Price_Rs__c`), two block expiry fields (`Blocked_Until__c`, `Block_Expiry_Date__c`) that no blocking code writes.
- **Unit blocking** (`UnitBlockingController.saveUnitBlock:72-136`): validates days ≤ `Max_Unit_Block_Days__c`, inserts the history row and sets the plot Blocked in a savepoint, but does not re-check the plot is still Available. `QuoteApprovalTriggerHandler` also blocks the unit on quote creation with **no expiry** and releases it only on Rejected / Denied by Customer. `UnitBlockHistoryTrigger` frees the plot on Revoked regardless of other live holds. `UnitBlockExpiryScheduler.cls:20-21` only revokes rows expiring *today*; a missed day leaves the unit blocked forever. The sandbox has 0 scheduled jobs and 6 expired-but-Blocked rows, which is this defect in production form.
- **Master_Payment_Schedule__c** has two parallel field sets in git (legacy `S_No__c` / `Payment_Percent__c` / `Tower__c`, new `Sequence__c` / `Percentage__c` / `Applicable_For__c` / `Days_After_*` / `Is_Agreement__c`). The sandbox has only the legacy set. Three consumers read it differently: the quote cost sheet by Project + Tower ordered by `S_No__c` (`CreateQuoteController.cls:227-274`), the booking generator by Project + `Is_Active__c` + `Applicable_For__c` ordered by `Sequence__c` (`PaymentScheduleGeneratorService.cls:79-97`), and the VF quote page by Unit. `MasterPaymentScheduleTrigger` is off (`Enable_Master_Payment_Schedule_Trigger = false`).

### 3.8 Quote / cost sheet

`aura/CreateQuote` loads the lead's project, Available plots for it, the nine `Quote_Discount_Config__mdt` rows and the projects with a Completed site visit (advisory only). Picking a unit copies ~25 pricing fields from Plot to Quote **and computes all prices and discounts in the browser** (`CreateQuoteController.js:311-346, 589-627`); the server inserts what it receives (`CreateQuoteController.cls:160-172`, errors returned as `'ERROR: …'` strings). The JS also writes `New_Lead__c` and `Plot_Number__c`, fields absent from `Quote__c` in git *(not verified at runtime)*.

`QuoteTrigger` → `QuoteApprovalTriggerHandler`: maps manager hierarchy; compares each discount against the executive's `Discount_Limit__c` row for that project (absolute per-sqft amounts, not %); auto-approves if within limits, else submits to approval process `Quote_Approval` (not in source; skipped under test at `:256`); blocks the plot and inserts a block-history row with `Database.insert(…, false)` so picklist mismatches are swallowed. Executives with no limit row always go to manual approval. Statuses: Drafted → Submitted for Approval / Approved / Rejected → Accepted by Customer (set by the booking flow) / Denied by Customer. `QuoteController.sendEmailtoCustomer` allows Drafted quotes and only has a PDF template for `'The Legacey'` (`:16,23`); sender is a personal Gmail from a custom label.

### 3.9 Quote → Booking

`aura/CreateBooking` pre-fills a Booking from the Quote (post-discount prices), project advance amount, today's date. `BookingController.createBook:37-116`: requires `Plot.Status__c == 'Blocked'` (not that the block belongs to this lead or that the quote is Approved); copies project roles; `CLead__c = Quote.CLead__c`; `upsert`; sets the plot Booked and the lead `Booked` (which cancels Scheduled site visits, leaves follow-ups); inserts co-applicants; returns the Id **or an error string that the JS navigates to as if it were an Id**.

On save the Booking flows run in undefined order: `Booking_Map_Project_Users` (reads `Project__c`, but the UI fills `Project1__c`), `Record_Type_Appartment` (hard-coded record type Id on every booking), `Update_booking_Stage` (forces the quote to Accepted by Customer regardless of approval), `Booking_After_Create_Handler` (field mapper → `PaymentScheduleGeneratorService` → advance receipt from `Booking_Amount__c`, while the UI fills `Booking_Amount1__c`). **None of these flows exist in the sandbox**, and the sandbox `Booking__c` has `Stage__c`, not `Status__c`. The two bookings there were created with no payment schedules generated by this code.

---

## 4. Gaps and risks, ranked

| # | Risk | Evidence | Impact |
|---|---|---|---|
| 1 | Insert-time dedupe is inert | `RelatedSourceHandler.cls:155-166` keys on formula fields; 48 identical leads on one phone, `Main_Lead__c` = 0/832 | Duplicate leads round-robined to different executives, double calls, re-open/re-engage never triggers, API returns Ids of leads it believes were merged |
| 2 | No scheduled jobs in the sandbox | `CronTrigger` count 0; 6 expired Blocked holds | Units stay blocked, availability never resets, temp assignments never expire |
| 3 | Status machine unenforced; case split | unrestricted picklist; `'New sales enquiry'` at `LeadTrigger:27,50,152`, `pushToSalesController:22` vs picklist `New Sales Enquiry`; 724 leads in New Enquiry incl. 17 with follow-ups | Pipeline reporting is wrong; UI auto-transitions never fire for walk-in / pushed leads |
| 4 | Availability is advisory | fallback pool `RoundRobinHandler:27,76`; nightly reset `UserAvailabilityOffScheduler:10-26` | Leads assigned to people who said they are off; no "nobody available" alert |
| 5 | Standard-Lead code paths dead or broken | `pushToSalesController:100,106`, `RelatedSourceTrigger:37-138`, `GRE_Lead_Controller:170-177`; SLead__c = 0 everywhere | Guards that never fire, CP sharing that never happens, one insert that fails |
| 6 | GRE hand-off bypasses the push controller | `GRE_Lead_Controller:270-387`; `js:832-896` sets RT/owner/status client-side; blind `update` at `:302` | Children not re-owned, `IsPushed__c` unset, mass-assignment from the browser |
| 7 | Quote pricing and discount caps enforced only in the browser | `CreateQuoteController.cls:160-172`; `CreateQuoteHelper.js:47-70` | Any user can post any amount; approval routing then trusts those amounts |
| 8 | Unit block lifecycle leaks | no Available re-check (`UnitBlockingController:122`, `QuoteApprovalTriggerHandler:79`); quote blocks never expire; revoke frees plot despite other holds; `Converted` never written; 45 Blocked histories vs 7 blocked plots | Inventory status unreliable; two leads can hold one unit |
| 9 | Project identity by three keys | `CreateQuoteController:49,130`, `UnitBlockingController:38,50,95`, `QuoteApprovalTriggerHandler:218-233` | Renaming a project or a picklist label silently breaks quotes and blocking |
| 10 | Booking automation keyed on fields the UI does not fill | `Booking_Map_Project_Users` reads `Project__c`, UI fills `Project1__c`; handler reads `Booking_Amount__c`, UI fills `Booking_Amount1__c`; hard-coded RT Id | Works only if the field mapper bridges them; breaks in any other org |
| 11 | Drizzle has no master schedule; sandbox MPS lacks the new fields | data snapshot; `PaymentScheduleGeneratorService:93-97` | Drizzle bookings get zero milestones; git generator cannot run here |
| 12 | Notifications misdirected | follow-up reminder to `CreatedById` (`Follow_Ups_Assignment:50-56`); site-visit reminder only after push; agenda uses wrong status literals (`HomeNotificationController:26,34`) | Executives miss follow-ups and visits |
| 13 | Telephony auto-dial on every enquiry row | `RelatedSourceTrigger:63-66`; hard-coded unauthenticated AWS URL | Customers dialled on re-engagement and merge; errors invisible |
| 14 | Merge and bulk reassignment leave orphans | `LeadMergeController:98-157`; `BulkLeadReassignmentController:153-157`; `TempAssignmentExpiryBatch:41-56` | Quotes/bookings stranded on deleted leads; pre-sales users lose visibility on expiry |
| 15 | Dead and unused configuration | `Round_Robin_Off__c` ignored for Pre Sales; `Enquiry_Source__c` legacy; `Project__c.Enable_Auto_Unit_Unblocking__c` unread; 7 orphan RR members; `CP Expired Leads` source never set; `transferLeadController.moveToSales` commented | Admins configure things that do nothing |

---

## 5. What is sound

- Round-robin distribution is even in practice (240 / 236 / 224) and the least-recently-assigned ordering is correct within a single transaction.
- Push-to-sales keeps the pre-sales executive's visibility through explicit `Lead__Share` / `Follow_up__Share` rows, which is the right pattern for a Private OWD object.
- Follow-up validation rules are sensible (completed date, remarks, call duration mandatory; no past scheduling; pre-sales cannot create follow-ups on sales leads).
- Unit blocking has input validation, a savepoint and an audit object with reason, duration and who-revoked fields.
- Quote approval routing is metadata-driven (`Quote_Discount_Config__mdt` + `Discount_Limit__c` per executive and project) and resolves the manager hierarchy in two queries.
- `LeadPushAPI` logs every request, returns proper HTTP codes and validates the one mandatory field.
- The `Reassignment_History__c` audit and the temporary-assignment model are well designed, even if the expiry job is not running.

---

## 6. Recommended order of work (pre-sales only)

**Week 1**
1. Fix dedupe: key `duplicateCheck2` on `Phone__c` / `Secondary_Phone__c` directly (restore the pattern from the commented `:70-148`), add e-mail, decide whether the key is phone-only or phone+project, and backfill `Main_Lead__c` for the existing duplicates (253 leads in the top ten phones alone).
2. Schedule the three jobs in the sandbox (`UnitBlockExpiryScheduler`, `UserAvailabilityOffScheduler`, `TempAssignmentExpiryScheduler`) and change the expiry query to `Blocked_Expiry_Date__c <= NOW()`.
3. Normalise `'New sales enquiry'` to the picklist value in the four code sites and make `Lead_Status__c` restricted.
4. Delete or rewrite the four `SLead__c` code paths; remove the standard Lead bridge if web-to-lead is not in use.

**Month 1**
5. Replace the inline `LeadTrigger` with a handler class; add a real recursion guard; move the nine profile names to custom metadata.
6. Make availability a hard gate (remove the fallback query, or fall back only to a named "overflow" user) and post a notification when no member is available.
7. Move quote price computation and discount-cap validation server-side; reject quotes whose totals do not recompute.
8. Route the GRE hand-off through `pushToSalesController`; stop the client from setting RT, owner, status and `Lead_Type__c`.
9. Add an Available re-check inside the unit-block savepoint; give quote blocks an expiry; write `Converted` on booking.

**Quarter**
10. Collapse the three project identities to the `Project__c` lookup everywhere.
11. Add a `Lead_Status__c` transition validation rule or Apex state table, and fix the agenda/notification literals.
12. Reconcile the master-schedule field sets between git and the sandbox before deploying the booking generator; add a master schedule for The Drizzle.
13. Retire `Enquiry_Source__c`, `New_Lead__c`, duplicate Plot pricing fields, and the orphan round-robin members.

---

*Method: 24 object definitions and their picklists / validation rules read from source; 45 classes, 11 triggers, 10 flows and 12 UI bundles walked for the process map; 30 read-only SOQL queries against `anandasbox`. No metadata deployed, no data changed.*
