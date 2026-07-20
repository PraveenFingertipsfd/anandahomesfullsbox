/**
 * @description VF Page Controller for DynamicDocumentPDF.
 * Reads the Document_Template__c by the templateId URL parameter,
 * resolves it against the record identified by the id parameter,
 * and exposes the resulting HTML to the VF page.
 */
public with sharing class DynamicDocumentPDFController {

    // Configurable PDF defaults
    private static final String DEFAULT_PAGE_SIZE = 'A4';
    private static final String DEFAULT_ORIENTATION = 'portrait';
    private static final String DEFAULT_MARGIN_TOP = '20';
    private static final String DEFAULT_MARGIN_RIGHT = '15';
    private static final String DEFAULT_MARGIN_BOTTOM = '20';
    private static final String DEFAULT_MARGIN_LEFT = '15';
    private static final String DEFAULT_FONT_FAMILY = 'Arial, Helvetica, sans-serif';

    public String renderedHtml { get; set; }
    public String pageSize { get; set; }
    public String pageOrientation { get; set; }
    public String documentTitle { get; set; }
    public String marginTop { get; set; }
    public String marginRight { get; set; }
    public String marginBottom { get; set; }
    public String marginLeft { get; set; }
    public String fontFamily { get; set; }

    /** format=word renders MS Word; format=html renders a plain HTML view (used by the
     *  in-app Document Viewer so it looks exactly like the designer config preview). */
    private Boolean isWord = false;
    private Boolean isHtml = false;

    /** renderAs value for the VF page: 'pdf' for PDF, blank (HTML) for Word/HTML view. */
    public String getRenderAsFormat() {
        return (isWord || isHtml) ? null : 'pdf';
    }

    /** contentType for the VF page: msword download for Word, default otherwise. */
    public String getContentTypeValue() {
        if (!isWord) return null;
        String t = String.isNotBlank(documentTitle) ? documentTitle : 'Document';
        return 'application/msword#' + t + '.doc';
    }

    /** Body styling. The HTML view paints a gray canvas behind a centered A4 "page" so it
     *  looks exactly like the designer preview; the PDF/Word body is plain (the @page rule
     *  handles the physical page + margins). */
    public String getBodyStyle() {
        return isHtml
            ? 'background:#e2e2e2;margin:0;padding:24px 0;'
            : 'margin:0;padding:0;';
    }

    /** The page wrapper. For the HTML view this is the A4 "page canvas" (same 595px width and
     *  40px/36px padding as the designer preview) so spacing and line wrapping match. For
     *  PDF/Word it stays unstyled because the @page rule defines the real page geometry. */
    public String getPageStyle() {
        return isHtml
            ? 'width:595px;min-height:842px;margin:0 auto;background:#fff;'
              + 'padding:40px 36px;box-shadow:0 2px 12px rgba(0,0,0,0.15);box-sizing:border-box;'
            : '';
    }

    /** The HTML view keeps browser-default paragraph spacing so it matches the designer
     *  preview exactly (1em <p> margins that COLLAPSE to a single ~12px gap). The PDF/Word
     *  engine (Flying Saucer) does NOT collapse margins, so default top+bottom margins would
     *  double to ~24px gaps. We therefore give it BOTTOM-ONLY margins of the same size, which
     *  reproduces the browser's single-gap spacing — so the download matches preview & view. */
    public String getParagraphCss() {
        if (isHtml) return '';
        return 'p{margin:0 0 1em 0;}'
             + 'ul,ol{margin:0 0 1em 0;}'
             + 'h1,h2,h3,h4,h5,h6{margin:0.5em 0 0.25em 0;}';
    }

    private void setDefaults() {
        pageSize = DEFAULT_PAGE_SIZE;
        pageOrientation = DEFAULT_ORIENTATION;
        marginTop = DEFAULT_MARGIN_TOP;
        marginRight = DEFAULT_MARGIN_RIGHT;
        marginBottom = DEFAULT_MARGIN_BOTTOM;
        marginLeft = DEFAULT_MARGIN_LEFT;
        fontFamily = DEFAULT_FONT_FAMILY;
    }

    public DynamicDocumentPDFController() {
        setDefaults();
        String fmt = ApexPages.currentPage().getParameters().get('format');
        isWord = 'word'.equalsIgnoreCase(fmt);
        isHtml = 'html'.equalsIgnoreCase(fmt);
        try {
            String templateId = ApexPages.currentPage().getParameters().get('templateId');
            String recordId   = ApexPages.currentPage().getParameters().get('id');

            if (String.isBlank(templateId)) {
                renderedHtml = '<p style="color:red;">Missing templateId parameter.</p>';
                documentTitle = 'Document';
                return;
            }

            // Fetch template
            List<Document_Template__c> templates = [
                SELECT Id, Name, Object_API_Name__c, Template_JSON__c,
                       Template_Content_Document_Id__c,
                       Page_Size__c, Page_Orientation__c, Logo_URL__c
                FROM Document_Template__c
                WHERE Id = :templateId
                LIMIT 1
            ];

            if (templates.isEmpty()) {
                renderedHtml = '<p style="color:red;">Template not found.</p>';
                documentTitle = 'Document';
                return;
            }

            Document_Template__c template = templates[0];
            documentTitle = template.Name;
            pageSize = String.isNotBlank(template.Page_Size__c) ? template.Page_Size__c : DEFAULT_PAGE_SIZE;
            pageOrientation = String.isNotBlank(template.Page_Orientation__c) ? template.Page_Orientation__c : DEFAULT_ORIENTATION;

            // Load template JSON from ContentVersion (primary) or field (legacy)
            String templateJsonStr = TemplateJsonStorageService.loadTemplateJson(template);
            if (String.isNotBlank(templateJsonStr)) {
                Map<String, Object> tJson = (Map<String, Object>) JSON.deserializeUntyped(templateJsonStr);

                // Inject logo URL if set at template level
                if (String.isNotBlank(template.Logo_URL__c) && tJson.containsKey('header')) {
                    Map<String, Object> header = (Map<String, Object>) tJson.get('header');
                    if (String.isBlank((String) header.get('logoUrl'))) {
                        header.put('logoUrl', template.Logo_URL__c);
                        header.put('showLogo', true);
                        // Try to extract ContentVersion ID from URL for base64 conversion
                        if (String.isBlank((String) header.get('logoContentVersionId'))) {
                            String extractedCvId = extractContentVersionIdFromUrl(template.Logo_URL__c);
                            if (String.isNotBlank(extractedCvId)) {
                                header.put('logoContentVersionId', extractedCvId);
                            }
                        }
                    }
                    tJson.put('header', header);
                    templateJsonStr = JSON.serialize(tJson);
                }

                // ---- Collect all ContentVersion IDs for bulk base64 conversion ----
                // (single SOQL query instead of multiple queries in loops)
                Set<String> allCvIds = new Set<String>();

                if (tJson.containsKey('header')) {
                    Map<String, Object> hdr = (Map<String, Object>) tJson.get('header');

                    // Legacy single-column header logo
                    String cvId = (String) hdr.get('logoContentVersionId');
                    if (String.isBlank(cvId)) {
                        cvId = extractContentVersionIdFromUrl((String) hdr.get('logoUrl'));
                    }
                    if (String.isNotBlank(cvId)) allCvIds.add(cvId);

                    // 3-column header logos (left, center, right)
                    for (String colKey : new List<String>{'left', 'center', 'right'}) {
                        if (hdr.containsKey(colKey) && hdr.get(colKey) instanceof Map<String, Object>) {
                            Map<String, Object> col = (Map<String, Object>) hdr.get(colKey);
                            if ((String) col.get('type') == 'image') {
                                String colCvId = (String) col.get('logoContentVersionId');
                                if (String.isBlank(colCvId)) {
                                    colCvId = extractContentVersionIdFromUrl((String) col.get('logoUrl'));
                                    if (String.isNotBlank(colCvId)) col.put('logoContentVersionId', colCvId);
                                }
                                if (String.isNotBlank(colCvId)) allCvIds.add(colCvId);
                            }
                            hdr.put(colKey, col);
                        }
                    }
                    tJson.put('header', hdr);
                }

                // Section images
                if (tJson.containsKey('sections')) {
                    List<Object> sections = (List<Object>) tJson.get('sections');
                    for (Object sectionObj : sections) {
                        Map<String, Object> section = (Map<String, Object>) sectionObj;
                        if ((String) section.get('type') == 'image') {
                            String imgCvId = (String) section.get('imageContentVersionId');
                            if (String.isBlank(imgCvId)) {
                                imgCvId = extractContentVersionIdFromUrl((String) section.get('imageUrl'));
                                if (String.isNotBlank(imgCvId)) section.put('imageContentVersionId', imgCvId);
                            }
                            if (String.isNotBlank(imgCvId)) allCvIds.add(imgCvId);
                        }
                    }
                    tJson.put('sections', sections);
                }

                // ---- Bulk convert all collected ContentVersion IDs to base64 ----
                Map<String, String> base64Map = bulkConvertToBase64(allCvIds);

                // Apply base64 data URIs to header
                if (tJson.containsKey('header')) {
                    Map<String, Object> hdr = (Map<String, Object>) tJson.get('header');

                    // Legacy single-column header logo
                    String cvId = (String) hdr.get('logoContentVersionId');
                    if (String.isNotBlank(cvId) && base64Map.containsKey(cvId)) {
                        hdr.put('logoUrl', base64Map.get(cvId));
                        hdr.put('showLogo', true);
                    }

                    // 3-column header logos
                    for (String colKey : new List<String>{'left', 'center', 'right'}) {
                        if (hdr.containsKey(colKey) && hdr.get(colKey) instanceof Map<String, Object>) {
                            Map<String, Object> col = (Map<String, Object>) hdr.get(colKey);
                            if ((String) col.get('type') == 'image') {
                                String colCvId = (String) col.get('logoContentVersionId');
                                if (String.isNotBlank(colCvId) && base64Map.containsKey(colCvId)) {
                                    col.put('logoUrl', base64Map.get(colCvId));
                                }
                            }
                            hdr.put(colKey, col);
                        }
                    }
                    tJson.put('header', hdr);
                }

                // Apply base64 data URIs to section images
                if (tJson.containsKey('sections')) {
                    List<Object> sections = (List<Object>) tJson.get('sections');
                    for (Object sectionObj : sections) {
                        Map<String, Object> section = (Map<String, Object>) sectionObj;
                        if ((String) section.get('type') == 'image') {
                            String imgCvId = (String) section.get('imageContentVersionId');
                            if (String.isNotBlank(imgCvId) && base64Map.containsKey(imgCvId)) {
                                section.put('imageUrl', base64Map.get(imgCvId));
                            }
                        }
                    }
                    tJson.put('sections', sections);
                }

                templateJsonStr = JSON.serialize(tJson);

                // Extract page margins and font from styles
                if (tJson.containsKey('styles')) {
                    Map<String, Object> styles = (Map<String, Object>) tJson.get('styles');
                    if (styles.get('marginTop') != null) marginTop = String.valueOf(styles.get('marginTop'));
                    if (styles.get('marginRight') != null) marginRight = String.valueOf(styles.get('marginRight'));
                    if (styles.get('marginBottom') != null) marginBottom = String.valueOf(styles.get('marginBottom'));
                    if (styles.get('marginLeft') != null) marginLeft = String.valueOf(styles.get('marginLeft'));
                    if (styles.get('fontFamily') != null) {
                        String ff = String.valueOf(styles.get('fontFamily'));
                        if (String.isNotBlank(ff)) fontFamily = ff;
                    }
                }
            }

            if (String.isNotBlank(recordId)) {
                renderedHtml = DynamicDocumentRenderer.renderDocument(
                    templateJsonStr, recordId, template.Object_API_Name__c
                );
            } else {
                renderedHtml = DynamicDocumentRenderer.renderDocument(
                    templateJsonStr, null, template.Object_API_Name__c
                );
            }

            // Final safety net: rich-text sections (and any other content path)
            // can embed <img src="…sfc/servlet.shepherd/…"> tags directly in
            // their HTML. The PDF renderer can't auth-fetch those, so they
            // render as broken images. Sweep the whole rendered HTML and
            // resolve every Salesforce-shaped src to a public URL.
            renderedHtml = embedSalesforceImgSrcsAsBase64(renderedHtml);
        } catch (Exception e) {
            renderedHtml = '<p style="color:red;">Error rendering document: ' +
                           String.valueOf(e.getMessage()) + '</p>';
            documentTitle = 'Error';
        }
    }

    /**
     * @description Bulk-resolves a set of ContentVersion/ContentDocument Ids to URLs
     * that Visualforce's PDF renderer (Flying Saucer) can fetch.
     *
     * Why not base64 data URIs? Flying Saucer in Salesforce's PDF pipeline does NOT
     * reliably render <img src="data:..."> — debug logs confirmed a known-good
     * 16x16 PNG embedded as a data URI fails just like the real logo. So instead
     * we mint a public ContentDistribution URL per image (idempotent — reuses any
     * existing distribution) and emit that as the img src. The PDF engine fetches
     * it just like a browser would.
     *
     * Falls back to base64 if ContentDistribution can't be created (org doesn't
     * have Content Deliveries enabled) so callers don't crash.
     */
    private static Map<String, String> bulkConvertToBase64(Set<String> contentVersionIds) {
        return new ImageBase64Helper().convertForPdf(contentVersionIds);
    }

    /**
     * Inner class that runs without sharing to ensure ContentVersion images
     * are accessible regardless of which user uploaded them.
     */
    private without sharing class ImageBase64Helper {
        public Map<String, String> convertForPdf(Set<String> imageIds) {
            Map<String, String> result = new Map<String, String>();
            if (imageIds == null || imageIds.isEmpty()) return result;

            imageIds.remove(null);
            imageIds.remove('');
            if (imageIds.isEmpty()) return result;

            // Split inputs by prefix: 068 = ContentVersion, 069 = ContentDocument.
            Set<Id> versionIds = new Set<Id>();
            Set<Id> documentIds = new Set<Id>();
            Map<Id, String> originalIdFor = new Map<Id, String>(); // resolvedCvId -> originalCallerId

            for (String raw : imageIds) {
                Id sid;
                try { sid = (Id) raw; } catch (Exception ignored) { continue; }
                String prefix = String.valueOf(sid).substring(0, 3);
                if (prefix == '068') {
                    versionIds.add(sid);
                    originalIdFor.put(sid, raw);
                } else if (prefix == '069') {
                    documentIds.add(sid);
                }
            }

            if (!documentIds.isEmpty()) {
                try {
                    for (ContentDocument cd : [
                        SELECT Id, LatestPublishedVersionId
                        FROM ContentDocument
                        WHERE Id IN :documentIds
                    ]) {
                        if (cd.LatestPublishedVersionId != null) {
                            versionIds.add(cd.LatestPublishedVersionId);
                            originalIdFor.put(cd.LatestPublishedVersionId, cd.Id);
                        }
                    }
                } catch (Exception e) {
                    System.debug('ContentDocument -> Version lookup failed: ' + e.getMessage());
                }
            }

            if (versionIds.isEmpty()) return result;

            // ---- Step 1: try public ContentDistribution URLs (preferred) ----
            Map<Id, String> publicUrlByCvId = getOrCreatePublicUrls(versionIds);
            System.debug('PDF-img: public URLs obtained=' + publicUrlByCvId.size()
                + ' of ' + versionIds.size() + ' versions');

            // ---- Step 2: fall back to base64 for any version we couldn't publish ----
            Set<Id> needBase64 = new Set<Id>();
            for (Id vid : versionIds) {
                if (!publicUrlByCvId.containsKey(vid)) needBase64.add(vid);
            }
            Map<Id, String> base64ByCvId = new Map<Id, String>();
            if (!needBase64.isEmpty()) {
                try {
                    for (ContentVersion cv : [
                        SELECT Id, VersionData, FileExtension
                        FROM ContentVersion
                        WHERE Id IN :needBase64
                    ]) {
                        if (cv.VersionData == null) continue;
                        String ext = (cv.FileExtension != null) ? cv.FileExtension.toLowerCase() : 'png';
                        String mimeType = 'image/png';
                        if (ext == 'jpg' || ext == 'jpeg') mimeType = 'image/jpeg';
                        else if (ext == 'gif') mimeType = 'image/gif';
                        else if (ext == 'svg') mimeType = 'image/svg+xml';
                        base64ByCvId.put(cv.Id, 'data:' + mimeType + ';base64,'
                            + EncodingUtil.base64Encode(cv.VersionData));
                    }
                } catch (Exception e) {
                    System.debug('base64 fallback failed: ' + e.getMessage());
                }
            }

            for (Id vid : versionIds) {
                String url = publicUrlByCvId.get(vid);
                if (String.isBlank(url)) url = base64ByCvId.get(vid);
                if (String.isBlank(url)) continue;
                String originalKey = originalIdFor.get(vid);
                if (originalKey != null) result.put(originalKey, url);
                result.put(String.valueOf(vid), url);
            }
            return result;
        }

        /**
         * @description For each ContentVersion Id, returns its public
         * ContentDistribution URL — reusing an existing one if available, otherwise
         * creating a new one. Returns an empty map if Content Deliveries isn't
         * enabled in the org (caller falls back to base64).
         */
        private Map<Id, String> getOrCreatePublicUrls(Set<Id> versionIds) {
            Map<Id, String> result = new Map<Id, String>();
            if (versionIds == null || versionIds.isEmpty()) return result;

            try {
                // Find existing distributions first.
                for (ContentDistribution cd : [
                    SELECT Id, ContentVersionId, DistributionPublicUrl, ContentDownloadUrl
                    FROM ContentDistribution
                    WHERE ContentVersionId IN :versionIds
                ]) {
                    String url = cd.ContentDownloadUrl;
                    if (String.isBlank(url)) url = cd.DistributionPublicUrl;
                    if (String.isNotBlank(url)) result.put(cd.ContentVersionId, url);
                }
            } catch (Exception e) {
                System.debug('ContentDistribution query failed (Content Deliveries may not be enabled): ' + e.getMessage());
                return result;
            }

            // Create distributions for any version we don't have a URL for yet.
            List<ContentDistribution> toInsert = new List<ContentDistribution>();
            for (Id vid : versionIds) {
                if (result.containsKey(vid)) continue;
                ContentDistribution cd = new ContentDistribution();
                cd.Name = 'PDF Render: ' + vid;
                cd.ContentVersionId = vid;
                cd.PreferencesAllowOriginalDownload = true;
                cd.PreferencesAllowPDFDownload = true;
                cd.PreferencesAllowViewInBrowser = true;
                cd.PreferencesNotifyOnVisit = false;
                cd.PreferencesPasswordRequired = false;
                cd.PreferencesLinkLatestVersion = true;
                toInsert.add(cd);
            }
            if (!toInsert.isEmpty()) {
                try {
                    Database.SaveResult[] results = Database.insert(toInsert, false);
                    Set<Id> newCdIds = new Set<Id>();
                    for (Database.SaveResult sr : results) {
                        if (sr.isSuccess()) newCdIds.add(sr.getId());
                        else System.debug('ContentDistribution insert error: ' + sr.getErrors());
                    }
                    if (!newCdIds.isEmpty()) {
                        for (ContentDistribution cd : [
                            SELECT Id, ContentVersionId, DistributionPublicUrl, ContentDownloadUrl
                            FROM ContentDistribution
                            WHERE Id IN :newCdIds
                        ]) {
                            String url = cd.ContentDownloadUrl;
                            if (String.isBlank(url)) url = cd.DistributionPublicUrl;
                            if (String.isNotBlank(url)) result.put(cd.ContentVersionId, url);
                        }
                    }
                } catch (Exception e) {
                    System.debug('ContentDistribution insert failed: ' + e.getMessage());
                }
            }
            return result;
        }
    }

    /**
     * @description Converts a ContentVersion logo to a base64 data URI
     * for reliable embedding in PDF output (avoids external URL fetching issues).
     */
    private static String convertLogoToBase64(String contentVersionId) {
        Set<String> ids = new Set<String>{ contentVersionId };
        Map<String, String> results = bulkConvertToBase64(ids);
        return results.get(contentVersionId);
    }

    /**
     * @description Walks the rendered HTML looking for <img> tags whose src
     * points at a Salesforce content URL (or a bare 068/069 Id), and rewrites
     * each src to a base64 data URI. Idempotent — already-converted data:
     * URIs are left untouched.
     */
    private static String embedSalesforceImgSrcsAsBase64(String html) {
        if (String.isBlank(html) || html.indexOf('<img') < 0) return html;

        // Find every src="…" or src='…' on an <img> tag.
        Pattern pat = Pattern.compile(
            '(?i)<img\\b[^>]*?\\bsrc\\s*=\\s*([\"\\\'])([^\"\\\']+)\\1'
        );
        Matcher m = pat.matcher(html);

        // First pass: collect Ids we need to fetch.
        Set<String> idsNeeded = new Set<String>();
        Map<String, String> srcToId = new Map<String, String>();
        Integer totalImgTags = 0;
        Integer unresolvableSrcs = 0;
        List<String> sampleUnresolved = new List<String>();
        while (m.find()) {
            totalImgTags++;
            String src = m.group(2);
            if (String.isBlank(src) || src.startsWith('data:')) continue;
            String cid = extractContentVersionIdFromUrl(src);
            if (String.isNotBlank(cid)) {
                idsNeeded.add(cid);
                srcToId.put(src, cid);
            } else {
                unresolvableSrcs++;
                if (sampleUnresolved.size() < 3) {
                    // Truncate to keep logs short.
                    sampleUnresolved.add(src.length() > 200 ? src.substring(0, 200) + '…' : src);
                }
            }
        }
        System.debug('PDF-img: total <img>=' + totalImgTags
            + ', ids extracted=' + idsNeeded.size()
            + ', unresolvable srcs=' + unresolvableSrcs
            + (sampleUnresolved.isEmpty() ? '' : ', samples=' + sampleUnresolved));
        if (idsNeeded.isEmpty()) return html;

        Map<String, String> base64Map = bulkConvertToBase64(idsNeeded);
        System.debug('PDF-img: requested base64 for ' + idsNeeded.size()
            + ' ids, got back ' + base64Map.size() + ' entries');
        if (base64Map.isEmpty()) return html;

        // Second pass: rewrite. Build a fresh string by walking matches in
        // order so overlapping replacements never collide.
        List<String> outParts = new List<String>();
        Integer cursor = 0;
        m = pat.matcher(html);
        while (m.find()) {
            String fullSrcExpr = m.group(0);       // <img …src="…">
            String quote = m.group(1);
            String src = m.group(2);
            Integer start = m.start();
            Integer endIdx = m.end();
            outParts.add(html.substring(cursor, start));

            String dataUri = null;
            if (!String.isBlank(src) && !src.startsWith('data:')) {
                String cid = srcToId.get(src);
                if (String.isNotBlank(cid)) dataUri = base64Map.get(cid);
            }
            if (String.isNotBlank(dataUri)) {
                outParts.add(fullSrcExpr.replace(quote + src + quote, quote + dataUri + quote));
            } else {
                outParts.add(fullSrcExpr);
            }
            cursor = endIdx;
        }
        outParts.add(html.substring(cursor));
        return String.join(outParts, '');
    }

    /**
     * @description Extract a Salesforce content Id (ContentVersion 068 or
     * ContentDocument 069) from a logo URL stored on a template. Handles every
     * common Lightning content URL shape the builder LWC might have written:
     *
     *   /sfc/servlet.shepherd/version/download/068...
     *   /sfc/servlet.shepherd/document/download/069...
     *   /sfc/dist/version/download/...
     *   /servlet/servlet.FileDownload?file=068...
     *   /lightning/r/ContentDocument/069.../view
     *   plain 15/18-char Id at the tail
     *
     * Returns null if no Id can be located. bulkConvertToBase64 below knows how
     * to handle both 068 and 069 prefixes, so we don't try to "upgrade" a
     * ContentDocument Id to its latest version here.
     */
    @TestVisible
    private static String extractContentVersionIdFromUrl(String url) {
        if (String.isBlank(url)) return null;

        // Quick path: caller passed a bare Id.
        String trimmed = url.trim();
        if ((trimmed.length() == 15 || trimmed.length() == 18)
            && (trimmed.startsWith('068') || trimmed.startsWith('069'))) {
            return trimmed;
        }

        // Marker-based extraction.
        List<String> markers = new List<String>{
            '/sfc/servlet.shepherd/version/download/',
            '/sfc/servlet.shepherd/document/download/',
            '/sfc/dist/version/download/',
            '/lightning/r/ContentDocument/',
            '/sobjects/ContentVersion/',
            '/sobjects/ContentDocument/',
            'file=',
            'documentId=',
            'contentDocumentId=',
            'versionId='
        };
        for (String marker : markers) {
            Integer idx = url.indexOf(marker);
            if (idx < 0) continue;
            String tail = url.substring(idx + marker.length());
            for (String sep : new List<String>{ '?', '&', '/', '#' }) {
                if (tail.contains(sep)) tail = tail.substringBefore(sep);
            }
            if ((tail.length() == 15 || tail.length() == 18)
                && (tail.startsWith('068') || tail.startsWith('069'))) {
                return tail;
            }
        }

        // Defensive fallback: scan anywhere in the URL for the first 068/069 Id.
        // Catches odd shapes like thumbnail/preview URLs, REST endpoints with
        // additional path segments, or any URL we haven't enumerated above.
        Matcher idMatcher = Pattern.compile('(068|069)[a-zA-Z0-9]{12,15}').matcher(url);
        if (idMatcher.find()) {
            String found = idMatcher.group(0);
            if (found.length() == 15 || found.length() == 18) return found;
            // Got 16 or 17 chars — almost certainly part of a longer token.
            if (found.length() > 15) return found.substring(0, 15);
        }
        return null;
    }

}