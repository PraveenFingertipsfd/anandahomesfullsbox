/**
 * @description Renders a Document_Template__c JSON definition into HTML.
 * Resolves merge fields from the primary record, parent lookups,
 * and child relationship tables. Used by both the VF PDF page and
 * the LWC preview.
 *
 * Template JSON structure:
 * {
 *   "header":  { "content": "html", "showLogo": true, "logoPosition": "left" },
 *   "footer":  { "content": "html", "showPageNumbers": true },
 *   "sections": [
 *     { "type": "content",   "content": "html with {!Field__c}" },
 *     { "type": "table",     "title": "...", "childObject": "...",
 *       "relationshipField": "...", "columns": [{"label":"...","field":"..."}],
 *       "orderBy": "...", "maxRows": 50, "showRowNumbers": true },
 *     { "type": "separator" }
 *   ],
 *   "styles": { "fontFamily": "...", "fontSize": "12px", "primaryColor": "#333" }
 * }
 *
 * Table sections support two modes:
 *  - Child table:       childObject + relationshipField set -> one row per child record.
 *  - Main-record table: childObject blank -> exactly ONE row sourced from the main
 *    record's own fields (direct like Amount__c or lookup paths like Booking__r.Amount__c).
 */
public with sharing class DynamicDocumentRenderer {

    // ============================== PUBLIC ENTRY POINT ==============================

    /**
     * @description Render complete document HTML from template JSON
     * @param templateJsonStr The Template_JSON__c value
     * @param recordId The source record ID
     * @param objectApiName The object API name
     * @return Fully resolved HTML string
     */
    public static String renderDocument(String templateJsonStr, String recordId, String objectApiName) {
        if (String.isBlank(templateJsonStr)) return '';

        Map<String, Object> template = (Map<String, Object>) JSON.deserializeUntyped(templateJsonStr);

        // Resolve styles
        Map<String, Object> styles = template.containsKey('styles')
            ? (Map<String, Object>) template.get('styles')
            : new Map<String, Object>();

        String fontFamily = getStr(styles, 'fontFamily', 'Arial, Helvetica, sans-serif');
        String fontSize   = getStr(styles, 'fontSize', '12px');
        String primaryColor = getStr(styles, 'primaryColor', '#333333');
        // Match the designer preview's typography exactly (preview uses line-height 1.6 and
        // browser-default paragraph spacing). The in-app document view renders this as HTML in
        // the browser, so it looks identical to the preview. Overridable via styles.lineHeight.
        String lineHeight = getStr(styles, 'lineHeight', '1.6');

        // Fetch primary record with all accessible fields + referenced parent fields
        SObject record = null;
        if (String.isNotBlank(recordId)) {
            record = queryRecord(recordId, objectApiName, templateJsonStr);
        }

        StringBuilder html = new StringBuilder();
        html.append('<div style="font-family:' + fontFamily + ';font-size:' + fontSize +
                    ';color:' + primaryColor + ';line-height:' + lineHeight + ';">');

        // ---- HEADER ----
        if (template.containsKey('header')) {
            html.append(renderHeader((Map<String, Object>) template.get('header'), record, objectApiName));
        }

        // ---- SECTIONS ----
        if (template.containsKey('sections')) {
            List<Object> sections = (List<Object>) template.get('sections');
            for (Object sectionObj : sections) {
                Map<String, Object> section = (Map<String, Object>) sectionObj;
                html.append(renderSection(section, record, recordId, objectApiName));
            }
        }

        // ---- FOOTER ----
        if (template.containsKey('footer')) {
            html.append(renderFooter((Map<String, Object>) template.get('footer'), record, objectApiName));
        }

        html.append('</div>');
        return html.toString();
    }

    // ============================== HEADER ==============================

    private static String renderHeader(Map<String, Object> header, SObject record, String objectApiName) {
        StringBuilder html = new StringBuilder();

        // Global header styling
        String hdrFontSize = getStr(header, 'fontSize', '');
        Boolean hdrBold = header.get('bold') == true;
        String hdrColor = getStr(header, 'textColor', '');
        String hdrStyle = 'padding-bottom:10px;margin-bottom:16px;';
        if (String.isNotBlank(hdrFontSize)) hdrStyle += 'font-size:' + hdrFontSize + ';';
        if (hdrBold) hdrStyle += 'font-weight:bold;';
        if (String.isNotBlank(hdrColor)) hdrStyle += 'color:' + hdrColor + ';';

        // Check for new 3-column format (has left/center/right keys)
        if (header.containsKey('left') || header.containsKey('center') || header.containsKey('right')) {
            html.append('<div style="' + hdrStyle + '">');
            html.append('<table style="width:100%;border:none;border-collapse:collapse;"><tr>');

            Map<String, Object> leftCol = header.containsKey('left') ? (Map<String, Object>) header.get('left') : null;
            Map<String, Object> centerCol = header.containsKey('center') ? (Map<String, Object>) header.get('center') : null;
            Map<String, Object> rightCol = header.containsKey('right') ? (Map<String, Object>) header.get('right') : null;

            html.append('<td style="width:33%;text-align:left;vertical-align:top;border:none;padding:0 4px 0 0;">');
            html.append(renderHeaderColumn(leftCol, record, objectApiName));
            html.append('</td>');

            html.append('<td style="width:34%;text-align:center;vertical-align:top;border:none;padding:0 4px;">');
            html.append(renderHeaderColumn(centerCol, record, objectApiName));
            html.append('</td>');

            html.append('<td style="width:33%;text-align:right;vertical-align:top;border:none;padding:0 0 0 4px;">');
            html.append(renderHeaderColumn(rightCol, record, objectApiName));
            html.append('</td>');

            html.append('</tr></table>');
            html.append('</div>');
        } else {
            // Legacy single-column format
            html.append('<div style="' + hdrStyle + '">');

            Boolean showLogo = header.get('showLogo') == true;
            String logoUrl = getStr(header, 'logoUrl', '');
            String logoPosition = getStr(header, 'logoPosition', 'left');

            if (showLogo && String.isNotBlank(logoUrl)) {
                String align = logoPosition == 'center' ? 'center' : (logoPosition == 'right' ? 'right' : 'left');
                Integer size = readLogoSize(header);
                html.append('<div style="text-align:' + align + ';margin-bottom:8px;">');
                html.append('<img src="' + logoUrl + '" width="' + size + '"'
                    + ' style="width:' + size + 'px;height:auto;" />');
                html.append('</div>');
            }

            String content = getStr(header, 'content', '');
            if (String.isNotBlank(content)) {
                content = resolveMergeFields(content, record, objectApiName);
                html.append('<div>' + content + '</div>');
            }

            html.append('</div>');
        }

        return html.toString();
    }

    private static String renderHeaderColumn(Map<String, Object> col, SObject record, String objectApiName) {
        if (col == null) return '';
        String colType = getStr(col, 'type', 'none');
        if (colType == 'none') return '';

        StringBuilder html = new StringBuilder();
        if (colType == 'image') {
            String logoUrl = getStr(col, 'logoUrl', '');
            // Use the URL as-is: for PDF, the controller pre-converts to base64 data URIs;
            // for LWC preview, Salesforce URLs work directly in the browser.
            if (String.isNotBlank(logoUrl)) {
                Integer size = readLogoSize(col);
                // Width pins the box; height auto so Flying Saucer preserves aspect ratio.
                html.append('<img src="' + logoUrl + '" width="' + size + '"'
                    + ' style="width:' + size + 'px;height:auto;" />');
            }
        } else if (colType == 'text') {
            String content = getStr(col, 'content', '');
            if (String.isNotBlank(content)) {
                content = resolveMergeFields(content, record, objectApiName);
                html.append(content);
            }
        }
        return html.toString();
    }

    // ============================== FOOTER ==============================

    private static String renderFooter(Map<String, Object> footer, SObject record, String objectApiName) {
        StringBuilder html = new StringBuilder();
        String ftrFontSize = getStr(footer, 'fontSize', '10px');
        String ftrColor = getStr(footer, 'textColor', '#666666');
        html.append('<div style="border-top:1px solid #ccc;padding-top:10px;margin-top:20px;font-size:' +
                    ftrFontSize + ';color:' + ftrColor + ';">');

        String content = getStr(footer, 'content', '');
        if (String.isNotBlank(content)) {
            content = resolveMergeFields(content, record, objectApiName);
            html.append('<div>' + content + '</div>');
        }

        Boolean showPageNumbers = footer.get('showPageNumbers') == true;
        if (showPageNumbers) {
            String pageNumPos = getStr(footer, 'pageNumberPosition', 'center');
            html.append('<div style="text-align:' + pageNumPos + ';margin-top:4px;">Page <span class="pagenumber"/> of <span class="pagecount"/></div>');
        }

        html.append('</div>');
        return html.toString();
    }

    // ============================== SECTIONS ==============================

    private static String renderSection(Map<String, Object> section, SObject record,
                                         String recordId, String objectApiName) {
        String sectionType = getStr(section, 'type', 'content');

        if (sectionType == 'content') {
            return renderContentSection(section, record, objectApiName);
        } else if (sectionType == 'table') {
            return renderTableSection(section, record, recordId, objectApiName);
        } else if (sectionType == 'separator') {
            String style = getStr(section, 'style', 'solid');
            return '<hr style="border:none;border-top:1px ' + style + ' #ccc;margin:16px 0;" />';
        } else if (sectionType == 'heading') {
            return renderHeadingSection(section, record, objectApiName);
        } else if (sectionType == 'fieldGrid') {
            return renderFieldGridSection(section, record, objectApiName);
        } else if (sectionType == 'pageBreak') {
            return '<div style="page-break-after:always;"></div>';
        } else if (sectionType == 'image') {
            return renderImageSection(section, record, objectApiName);
        }

        return '';
    }

    // ---- CONTENT SECTION ----
    private static String renderContentSection(Map<String, Object> section, SObject record, String objectApiName) {
        String content = getStr(section, 'content', '');
        content = resolveMergeFields(content, record, objectApiName);

        // Section-level style overrides
        String bgColor = getStr(section, 'backgroundColor', 'transparent');
        String padding = getStr(section, 'padding', '8px 0');
        String textAlign = getStr(section, 'textAlign', 'left');
        String fontSize = getStr(section, 'fontSize', '');
        Boolean bold = section.get('bold') == true;
        String textColor = getStr(section, 'textColor', '');

        String style = 'background:' + bgColor + ';padding:' + padding + ';text-align:' + textAlign + ';';
        if (String.isNotBlank(fontSize)) style += 'font-size:' + fontSize + ';';
        if (bold) style += 'font-weight:bold;';
        if (String.isNotBlank(textColor)) style += 'color:' + textColor + ';';

        return '<div style="' + style + '">' + content + '</div>';
    }

    // ---- HEADING SECTION ----
    private static String renderHeadingSection(Map<String, Object> section, SObject record, String objectApiName) {
        String content = getStr(section, 'content', '');
        content = resolveMergeFields(content, record, objectApiName);
        String level = getStr(section, 'level', '2');
        String textAlign = getStr(section, 'textAlign', 'left');
        String textColor = getStr(section, 'textColor', '');

        String style = 'text-align:' + textAlign + ';margin:16px 0 8px 0;';
        if (String.isNotBlank(textColor)) style += 'color:' + textColor + ';';

        return '<h' + level + ' style="' + style + '">' + content + '</h' + level + '>';
    }

    // ---- FIELD GRID SECTION ----
    private static String renderFieldGridSection(Map<String, Object> section, SObject record, String objectApiName) {
        List<Object> fields = (List<Object>) section.get('fields');
        if (fields == null || fields.isEmpty()) return '';

        Integer cols = section.containsKey('gridColumns') ? Integer.valueOf(section.get('gridColumns')) :
                       (section.containsKey('columns') ? Integer.valueOf(section.get('columns')) : 2);
        String widthPct = String.valueOf(Math.floor(100 / cols)) + '%';

        StringBuilder html = new StringBuilder();
        html.append('<table style="width:100%;border-collapse:collapse;margin:8px 0;">');

        Integer count = 0;
        for (Object fieldObj : fields) {
            Map<String, Object> field = (Map<String, Object>) fieldObj;
            String label = getStr(field, 'label', '');
            String fieldName = getStr(field, 'field', '');

            if (Math.mod(count, cols) == 0) html.append('<tr>');

            String value = '';
            if (record != null && String.isNotBlank(fieldName)) {
                value = formatFieldValue(getFieldValue(record, fieldName));
            }

            html.append('<td style="padding:4px 8px;font-weight:bold;width:15%;border:1px solid #eee;background:#f9f9f9;">' + label + '</td>');
            html.append('<td style="padding:4px 8px;width:' + widthPct + ';border:1px solid #eee;">' + value + '</td>');

            count++;
            if (Math.mod(count, cols) == 0) html.append('</tr>');
        }

        // Close final row if needed
        if (Math.mod(count, cols) != 0) {
            Integer remaining = cols - Math.mod(count, cols);
            for (Integer i = 0; i < remaining; i++) {
                html.append('<td colspan="2" style="border:1px solid #eee;">&nbsp;</td>');
            }
            html.append('</tr>');
        }

        html.append('</table>');
        return html.toString();
    }

    // ---- IMAGE SECTION ----
    private static String renderImageSection(Map<String, Object> section, SObject record, String objectApiName) {
        String imageUrl = getStr(section, 'imageUrl', '');
        if (String.isNotBlank(imageUrl)) {
            imageUrl = resolveMergeFields(imageUrl, record, objectApiName);
        }
        if (String.isBlank(imageUrl)) return '';

        String textAlign = getStr(section, 'textAlign', 'center');
        String maxWidth = getStr(section, 'imageMaxWidth', '100%');
        String maxHeight = getStr(section, 'imageMaxHeight', 'auto');
        String caption = getStr(section, 'imageCaption', '');
        if (String.isNotBlank(caption)) {
            caption = resolveMergeFields(caption, record, objectApiName);
        }

        // Image URL is used as-is: for PDF, the controller pre-converts to base64 data URIs;
        // for LWC preview, Salesforce URLs work directly in the browser.

        StringBuilder html = new StringBuilder();
        html.append('<div style="text-align:' + textAlign + ';margin:12px 0;">');
        String dimAttrs = '';
        Integer hPx = pxToInt(maxHeight);
        Integer wPx = pxToInt(maxWidth);
        if (hPx != null) dimAttrs += ' height="' + hPx + '"';
        if (wPx != null) dimAttrs += ' width="' + wPx + '"';
        html.append('<img src="' + imageUrl + '"' + dimAttrs + ' />');
        if (String.isNotBlank(caption)) {
            html.append('<div style="font-size:10px;color:#666;margin-top:4px;font-style:italic;">' + caption + '</div>');
        }
        html.append('</div>');
        return html.toString();
    }

    // ---- TABLE SECTION (Child / Related Records OR Main-Record single row) ----
    // Two modes:
    //  1. Child table: childObject + relationshipField set -> one row per child record.
    //  2. Main-record table: childObject blank -> exactly ONE row whose values come
    //     from the main record itself. Column fields may be direct (Amount__c) or
    //     lookup paths (Booking__r.Amount__c); both resolve via getFieldValue and
    //     are already included in the main record query (all accessible fields +
    //     "field":"Rel.Field" paths scanned by addReferencedParentFields).
    private static String renderTableSection(Map<String, Object> section, SObject record,
                                              String recordId, String objectApiName) {
        String title = getStr(section, 'title', '');
        String childObject = getStr(section, 'childObject', '');
        String relationshipField = getStr(section, 'relationshipField', '');
        Integer maxRows = section.containsKey('maxRows') ? Integer.valueOf(section.get('maxRows')) : 50;
        String orderBy = getStr(section, 'orderBy', '');
        Boolean showRowNumbers = section.get('showRowNumbers') == true;
        List<Object> columns = (List<Object>) section.get('columns');

        // Blank childObject = main-record table (1 row from the parent record itself)
        Boolean isMainRecordTable = String.isBlank(childObject);

        if (columns == null || columns.isEmpty()) {
            return '<p style="color:red;">Table section missing configuration.</p>';
        }
        if (!isMainRecordTable && String.isBlank(relationshipField)) {
            return '<p style="color:red;">Table section missing configuration.</p>';
        }

        // Build column list
        List<String> fieldNames = new List<String>();
        List<String> columnLabels = new List<String>();
        for (Object colObj : columns) {
            Map<String, Object> col = (Map<String, Object>) colObj;
            fieldNames.add(getStr(col, 'field', 'Name'));
            columnLabels.add(getStr(col, 'label', ''));
        }

        // Rows: child records, or the main record itself as a single row
        List<SObject> children;
        if (isMainRecordTable) {
            children = (record != null) ? new List<SObject>{ record } : new List<SObject>();
        } else {
            children = queryChildRecords(
                childObject, relationshipField, recordId, fieldNames, orderBy, maxRows
            );
        }

        // Table styles
        String headerBg = getStr(section, 'headerBackground', '#f5f5f5');
        String headerColor = getStr(section, 'headerColor', '#333');
        String borderColor = getStr(section, 'borderColor', '#ddd');

        StringBuilder html = new StringBuilder();

        if (String.isNotBlank(title)) {
            html.append('<h3 style="margin:16px 0 6px 0;">' + title + '</h3>');
        }

        html.append('<table style="width:100%;border-collapse:collapse;margin-bottom:12px;">');

        // Header row
        html.append('<thead><tr>');
        if (showRowNumbers) {
            html.append('<th style="background:' + headerBg + ';color:' + headerColor +
                        ';border:1px solid ' + borderColor + ';padding:6px 8px;text-align:center;">Sl. No</th>');
        }
        for (String lbl : columnLabels) {
            html.append('<th style="background:' + headerBg + ';color:' + headerColor +
                        ';border:1px solid ' + borderColor + ';padding:6px 8px;text-align:left;">' + lbl + '</th>');
        }
        html.append('</tr></thead>');

        // Data rows
        html.append('<tbody>');
        if (children.isEmpty()) {
            Integer colSpan = columnLabels.size() + (showRowNumbers ? 1 : 0);
            html.append('<tr><td colspan="' + colSpan + '" style="border:1px solid ' + borderColor +
                        ';padding:8px;text-align:center;color:#999;">No records found</td></tr>');
        } else {
            Boolean alternateRowColors = section.get('alternateRowColors') == true;
            String altRowBg = getStr(section, 'alternateRowBackground', '#f9f9f9');
            Integer rowNum = 0;
            for (SObject child : children) {
                rowNum++;
                String rowBg = (alternateRowColors && Math.mod(rowNum, 2) == 0) ? altRowBg : 'transparent';
                html.append('<tr style="background:' + rowBg + ';">');
                if (showRowNumbers) {
                    html.append('<td style="border:1px solid ' + borderColor +
                                ';padding:4px 8px;text-align:center;">' + rowNum + '</td>');
                }
                for (String fName : fieldNames) {
                    Object val = getFieldValue(child, fName);
                    String display = formatFieldValue(val);
                    html.append('<td style="border:1px solid ' + borderColor +
                                ';padding:4px 8px;">' + display + '</td>');
                }
                html.append('</tr>');
            }
        }
        html.append('</tbody>');

        // ---- TOTALS ROW ----
        // Shown when "Show Totals" is on, or when any column has an aggregate configured.
        // For a main-record table the aggregates run over its single row (sum/min/max =
        // the value itself, count = 1); 'parent' still reads from the main record.
        Boolean anyAggregate = false;
        for (Object colObj : columns) {
            String agg = getStr((Map<String, Object>) colObj, 'total', 'none');
            if (String.isNotBlank(agg) && agg != 'none') { anyAggregate = true; break; }
        }
        if (section.get('showTotals') == true || anyAggregate) {
            String totalsLabel = getStr(section, 'totalsLabel', 'Total');
            html.append('<tfoot><tr style="font-weight:bold;background:' + headerBg + ';">');
            Boolean labelPlaced = false;
            if (showRowNumbers) {
                html.append('<td style="border:1px solid ' + borderColor +
                            ';padding:6px 8px;text-align:center;">' + totalsLabel + '</td>');
                labelPlaced = true;
            }
            for (Integer ci = 0; ci < fieldNames.size(); ci++) {
                Map<String, Object> col = (Map<String, Object>) columns[ci];
                String agg = getStr(col, 'total', 'none');
                String cellVal = '';
                if (agg == 'parent') {
                    String pf = getStr(col, 'totalParentField', '');
                    Object pv = (record != null && String.isNotBlank(pf)) ? getFieldValue(record, pf) : null;
                    cellVal = formatFieldValue(pv);
                } else if (agg == 'sum' || agg == 'count' || agg == 'average' || agg == 'min' || agg == 'max') {
                    cellVal = computeAggregate(children, fieldNames[ci], agg);
                } else if (!labelPlaced) {
                    // No aggregate for this column — use the first such cell to carry the label.
                    cellVal = totalsLabel;
                    labelPlaced = true;
                }
                html.append('<td style="border:1px solid ' + borderColor +
                            ';padding:6px 8px;">' + cellVal + '</td>');
            }
            html.append('</tr></tfoot>');
        }

        html.append('</table>');

        return html.toString();
    }

    // ============================== MERGE FIELD RESOLUTION ==============================

    private static String resolveMergeFields(String content, SObject record, String objectApiName) {
        if (record == null || String.isBlank(content)) return content;

        // ---- Function: {!INWORDS(Field__c)} -> the field's numeric value in words ----
        // (parentheses keep this from matching the plain {!Field} pattern below)
        Pattern fnP = Pattern.compile('(?i)\\{!\\s*INWORDS\\s*\\(\\s*([A-Za-z0-9_.]+)\\s*\\)\\s*\\}');
        Matcher fnM = fnP.matcher(content);
        Map<String, String> fnReplacements = new Map<String, String>();
        while (fnM.find()) {
            String fullMatch = fnM.group(0);
            String fieldPath = fnM.group(1);
            if (fieldPath.contains('.') && !fieldPath.contains('__r.')) {
                String prefix = fieldPath.substringBefore('.');
                if (prefix.equalsIgnoreCase(objectApiName)) fieldPath = fieldPath.substringAfter('.');
            }
            Object val = getFieldValue(record, fieldPath);
            String words = '';
            if (val != null) {
                try { words = numberToWordsIndian(Decimal.valueOf(String.valueOf(val))); }
                catch (Exception e) { words = ''; }
            }
            fnReplacements.put(fullMatch, words);
        }
        for (String key : fnReplacements.keySet()) {
            content = content.replace(key, fnReplacements.get(key));
        }

        // Pattern: {!FieldName__c} or {!Object__c.Field__c} or {!Parent__r.Field__c}
        Pattern p = Pattern.compile('\\{!([A-Za-z0-9_.]+)\\}');
        Matcher m = p.matcher(content);

        Map<String, String> replacements = new Map<String, String>();
        while (m.find()) {
            String fullMatch = m.group(0);
            String fieldPath = m.group(1);

            // Remove object prefix if present  e.g. {!Booking__c.Name} -> Name
            if (fieldPath.contains('.') && !fieldPath.contains('__r.')) {
                String prefix = fieldPath.substringBefore('.');
                // If prefix matches the object api name, strip it
                if (prefix.equalsIgnoreCase(objectApiName)) {
                    fieldPath = fieldPath.substringAfter('.');
                }
            }

            Object val = getFieldValue(record, fieldPath);
            replacements.put(fullMatch, formatFieldValue(val));
        }

        for (String key : replacements.keySet()) {
            content = content.replace(key, replacements.get(key));
        }

        // Resolve TODAY
        content = content.replace('{!TODAY}', String.valueOf(Date.today()));
        content = content.replace('{!NOW}', String.valueOf(Datetime.now()));

        return content;
    }

    // ============================== QUERY HELPERS ==============================

    private static SObject queryRecord(String recordId, String objectApiName, String templateJson) {
        if (String.isBlank(objectApiName)) {
            objectApiName = Id.valueOf(recordId).getSObjectType().getDescribe().getName();
        }

        Schema.SObjectType sType = Schema.getGlobalDescribe().get(objectApiName);
        if (sType == null) return null;

        Map<String, Schema.SObjectField> fieldMap = sType.getDescribe().fields.getMap();
        // Do NOT pre-populate with 'Id' — fieldMap.keySet() returns lowercase 'id'
        // and Apex Set is case-sensitive, so both 'Id' and 'id' would be added,
        // causing SOQL "Duplicate field selected" error.
        Set<String> fieldSet = new Set<String>();

        for (String fName : fieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = fieldMap.get(fName).getDescribe();
            if (dfr.isAccessible()) {
                // Skip compound fields (ADDRESS, LOCATION) as they cannot be queried directly
                Schema.DisplayType dt = dfr.getType();
                if (dt == Schema.DisplayType.ADDRESS || dt == Schema.DisplayType.LOCATION) {
                    continue;
                }
                fieldSet.add(fName);
            }
        }

        // Also include parent relationship fields for lookup traversals
        for (String fName : fieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = fieldMap.get(fName).getDescribe();
            if (dfr.isAccessible() && dfr.getType() == Schema.DisplayType.REFERENCE && !dfr.getReferenceTo().isEmpty()) {
                String relName = dfr.getRelationshipName();
                if (String.isNotBlank(relName)) {
                    fieldSet.add(relName + '.Name');
                }
            }
        }

        // Add any parent fields referenced in the template
        if (String.isNotBlank(templateJson)) {
            addReferencedParentFields(templateJson, fieldSet, fieldMap);
        }

        // Build clean field list — filter out any blank entries
        List<String> cleanFields = new List<String>();
        for (String f : fieldSet) {
            if (String.isNotBlank(f)) {
                cleanFields.add(f);
            }
        }
        if (cleanFields.isEmpty()) {
            cleanFields.add('Id');
        }

        String query = 'SELECT ' + String.join(cleanFields, ', ') +
                        ' FROM ' + String.escapeSingleQuotes(objectApiName) +
                        ' WHERE Id = :recordId LIMIT 1';

        try {
            List<SObject> records = Database.query(query);
            return records.isEmpty() ? null : records[0];
        } catch (Exception e) {
            // Fallback: query only Id and Name if full query fails
            try {
                String fallbackQuery = 'SELECT Id, Name FROM ' +
                                        String.escapeSingleQuotes(objectApiName) +
                                        ' WHERE Id = :recordId LIMIT 1';
                List<SObject> records = Database.query(fallbackQuery);
                return records.isEmpty() ? null : records[0];
            } catch (Exception e2) {
                return null;
            }
        }
    }

    private static List<SObject> queryChildRecords(String childObject, String relationshipField,
                                                     String parentRecordId, List<String> fieldNames,
                                                     String orderBy, Integer maxRows) {
        if (String.isBlank(childObject) || String.isBlank(relationshipField)) {
            return new List<SObject>();
        }

        // Ensure Id is always included, filter out blank entries
        Set<String> fieldSet = new Set<String>{'Id'};
        for (String f : fieldNames) {
            if (String.isNotBlank(f)) {
                fieldSet.add(String.escapeSingleQuotes(f));
            }
        }

        // Build clean field list
        List<String> cleanFields = new List<String>();
        for (String f : fieldSet) {
            if (String.isNotBlank(f)) {
                cleanFields.add(f);
            }
        }
        if (cleanFields.isEmpty()) {
            cleanFields.add('Id');
        }

        String query = 'SELECT ' + String.join(cleanFields, ', ') +
                        ' FROM ' + String.escapeSingleQuotes(childObject) +
                        ' WHERE ' + String.escapeSingleQuotes(relationshipField) + ' = :parentRecordId';

        if (String.isNotBlank(orderBy)) {
            query += ' ORDER BY ' + String.escapeSingleQuotes(orderBy);
        }

        query += ' LIMIT ' + maxRows;

        try {
            return Database.query(query);
        } catch (Exception e) {
            System.debug('Error querying child records: ' + e.getMessage() + ' | Query: ' + query);
            return new List<SObject>();
        }
    }

    // ============================== FIELD VALUE TRAVERSAL ==============================

    private static Object getFieldValue(SObject record, String fieldPath) {
        if (record == null || String.isBlank(fieldPath)) return null;

        try {
            if (fieldPath.contains('.')) {
                // Relationship traversal  e.g. Plot__r.Name
                String relName = fieldPath.substringBefore('.');
                String remaining = fieldPath.substringAfter('.');
                SObject parent = record.getSObject(relName);
                if (parent != null) {
                    return getFieldValue(parent, remaining);
                }
                return null;
            }
            return record.get(fieldPath);
        } catch (Exception e) {
            return null;
        }
    }

    // ============================== TEMPLATE FIELD SCANNING ==============================

    /**
     * @description Scan the template JSON for parent relationship field references
     * (e.g., Account__r.Phone, Owner.Email, and multi-hop grandparent paths like
     * Booking__r.Unit__r.Name) used in merge fields, fieldGrid sections, or table
     * columns, and add them to the query field set. The "field" scan (pattern 2)
     * also covers main-record TABLE columns that use lookup paths (Booking__r.Amount__c),
     * since table columns store their path under the same "field" key.
     *
     * Supports ANY relationship depth (Booking__r.Unit__r.Name,
     * Booking__r.Project__r.Owner__r.Name, etc.) — each hop is validated against schema
     * so a single bad/renamed field only skips that one merge field instead of throwing
     * and losing the whole query (which would blank out every merge field on the page).
     */
    private static void addReferencedParentFields(String templateJson, Set<String> fieldSet,
                                                    Map<String, Schema.SObjectField> fieldMap) {
        // 1. Scan for {!Relationship.Relationship....Field} patterns (any depth) in content
        Pattern p = Pattern.compile('\\{!([A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)+)\\}');
        Matcher m = p.matcher(templateJson);
        while (m.find()) {
            addValidatedPath(m.group(1), fieldSet, fieldMap);
        }

        // 1b. Scan inside {!INWORDS(...)} calls too — e.g. {!INWORDS(Booking__r.Unit__r.Cost__c)}
        Pattern fnP = Pattern.compile('(?i)\\{!\\s*INWORDS\\s*\\(\\s*([A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)+)\\s*\\)\\s*\\}');
        Matcher fnM = fnP.matcher(templateJson);
        while (fnM.find()) {
            addValidatedPath(fnM.group(1), fieldSet, fieldMap);
        }

        // 2. Scan for fieldGrid / table-column fields with dot notation (any depth)
        //    (e.g., "field":"Account__r.Phone" or "field":"Booking__r.Unit__r.Name")
        Pattern fieldPattern = Pattern.compile('"field"\\s*:\\s*"([A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)+)"');
        Matcher fm = fieldPattern.matcher(templateJson);
        while (fm.find()) {
            addValidatedPath(fm.group(1), fieldSet, fieldMap);
        }

        // 3. Scan for table-column parent-field totals with dot notation (any depth)
        //    (e.g., "totalParentField":"Booking__r.Unit__r.Total_Flat_Cost__c") so the value
        //    the totals row pulls from a related parent record is actually queried.
        Pattern totalPattern = Pattern.compile('"totalParentField"\\s*:\\s*"([A-Za-z0-9_]+(?:\\.[A-Za-z0-9_]+)+)"');
        Matcher tm = totalPattern.matcher(templateJson);
        while (tm.find()) {
            addValidatedPath(tm.group(1), fieldSet, fieldMap);
        }
    }

    /**
     * @description Walk a dotted relationship path (e.g. Booking__r.Unit__r.Name) one hop
     * at a time, validating each relationship segment against the schema of whatever object
     * it points to. If every hop resolves, the full path is added to the SOQL field set. If
     * any hop is invalid (typo'd relationship name, non-reference field, etc.) the path is
     * silently skipped — that single merge field just won't resolve, instead of throwing and
     * falling back to an Id/Name-only query that would blank out every merge field on the page.
     */
    private static void addValidatedPath(String fieldPath, Set<String> fieldSet,
                                          Map<String, Schema.SObjectField> rootFieldMap) {
        List<String> parts = fieldPath.split('\\.');
        if (parts.size() < 2) return; // no relationship hop — nothing extra to query

        Map<String, Schema.SObjectField> currentFieldMap = rootFieldMap;
        // Walk every segment except the last (the last segment is the actual field name)
        for (Integer i = 0; i < parts.size() - 1; i++) {
            Schema.SObjectField relField = findRelationshipField(parts[i], currentFieldMap);
            if (relField == null) return; // unknown relationship hop — bail out safely

            List<Schema.SObjectType> refs = relField.getDescribe().getReferenceTo();
            if (refs.isEmpty()) return; // polymorphic/unresolvable reference — bail out safely
            currentFieldMap = refs[0].getDescribe().fields.getMap();
        }

        fieldSet.add(fieldPath);
    }

    /** Finds the lookup field on fieldMap whose RelationshipName matches relName (case-insensitive). */
    private static Schema.SObjectField findRelationshipField(String relName, Map<String, Schema.SObjectField> fieldMap) {
        for (String fName : fieldMap.keySet()) {
            Schema.DescribeFieldResult dfr = fieldMap.get(fName).getDescribe();
            if (dfr.getType() == Schema.DisplayType.REFERENCE) {
                String lookupRelName = dfr.getRelationshipName();
                if (String.isNotBlank(lookupRelName) && lookupRelName.equalsIgnoreCase(relName)) {
                    return fieldMap.get(fName);
                }
            }
        }
        return null;
    }

    // ============================== UTILITIES ==============================

    // ============================== NUMBER TO WORDS (Indian) ==============================

    private static final List<String> ONES = new List<String>{
        '', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten',
        'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen', 'Seventeen', 'Eighteen', 'Nineteen'
    };
    private static final List<String> TENS = new List<String>{
        '', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'
    };

    /** Converts an amount to words using the Indian numbering system (Crore / Lakh / Thousand).
     *  Returns e.g. "One Lakh Twenty Three Thousand Four Hundred Fifty" (no currency word, so the
     *  template author can wrap it as "Rupees ... Only"). Includes paise when present. */
    @TestVisible
    private static String numberToWordsIndian(Decimal amount) {
        if (amount == null) return '';
        Boolean negative = amount < 0;
        if (negative) amount = amount.abs();

        Long rupees = amount.longValue();
        Decimal fraction = (amount - rupees) * 100;
        Integer paise = fraction.setScale(0, System.RoundingMode.HALF_UP).intValue();
        if (paise >= 100) { rupees += 1; paise -= 100; }

        String result = (rupees == 0) ? 'Zero' : convertToIndianWords(rupees);
        if (paise > 0) {
            result += ' and ' + twoDigits(paise) + ' Paise';
        }
        return (negative ? 'Minus ' : '') + result;
    }

    private static String twoDigits(Integer n) {
        if (n < 20) return ONES[n];
        Integer t = n / 10;
        Integer o = Math.mod(n, 10);
        return TENS[t] + (o > 0 ? ' ' + ONES[o] : '');
    }

    private static String threeDigits(Integer n) {
        Integer h = n / 100;
        Integer rest = Math.mod(n, 100);
        String s = '';
        if (h > 0) s += ONES[h] + ' Hundred';
        if (rest > 0) s += (s != '' ? ' ' : '') + twoDigits(rest);
        return s;
    }

    private static String convertToIndianWords(Long num) {
        if (num == 0) return '';
        String result = '';
        Long crore = num / 10000000;
        Long afterCrore = Math.mod(num, 10000000);
        Integer lakh = Integer.valueOf(String.valueOf(afterCrore / 100000));
        Long afterLakh = Math.mod(afterCrore, 100000);
        Integer thousand = Integer.valueOf(String.valueOf(afterLakh / 1000));
        Integer hundred = Integer.valueOf(String.valueOf(Math.mod(afterLakh, 1000)));

        if (crore > 0) result += convertToIndianWords(crore) + ' Crore ';
        if (lakh > 0) result += twoDigits(lakh) + ' Lakh ';
        if (thousand > 0) result += twoDigits(thousand) + ' Thousand ';
        if (hundred > 0) result += threeDigits(hundred);
        return result.trim();
    }

    // ============================== TABLE AGGREGATES ==============================

    /** Computes an aggregate (sum/count/average/min/max) over a child field. */
    private static String computeAggregate(List<SObject> children, String fieldName, String agg) {
        Decimal sum = 0;
        Integer cnt = 0;
        Decimal minV = null;
        Decimal maxV = null;
        for (SObject child : children) {
            Object v = getFieldValue(child, fieldName);
            if (v == null) continue;
            Decimal d;
            try { d = Decimal.valueOf(String.valueOf(v)); } catch (Exception e) { continue; }
            sum += d;
            cnt++;
            if (minV == null || d < minV) minV = d;
            if (maxV == null || d > maxV) maxV = d;
        }
        if (agg == 'count') return String.valueOf(cnt);
        if (cnt == 0) return '';
        if (agg == 'sum') return formatNumber(sum);
        if (agg == 'average') return formatNumber((sum / cnt).setScale(2));
        if (agg == 'min') return formatNumber(minV);
        if (agg == 'max') return formatNumber(maxV);
        return '';
    }

    /** Trims a trailing ".0" so whole numbers render cleanly. */
    private static String formatNumber(Decimal d) {
        if (d == null) return '';
        if (d == d.round()) return String.valueOf(d.longValue());
        return String.valueOf(d);
    }

    /**
     * @description Renders a field value for display in a document. DateTime fields show the
     *              calendar date only (no "00:00:00" time component) — documents display dates,
     *              not timestamps. Everything else is unchanged: a Date already renders as
     *              yyyy-MM-dd, and numbers/text/booleans pass through String.valueOf.
     */
    private static String formatFieldValue(Object val) {
        if (val == null) return '';
        if (val instanceof DateTime) {
            return ((DateTime) val).format('yyyy-MM-dd');
        }
        return String.valueOf(val);
    }

    private static String getStr(Map<String, Object> data, String key, String defaultVal) {
        if (data == null || !data.containsKey(key) || data.get(key) == null) return defaultVal;
        String val = String.valueOf(data.get(key));
        // Return default for empty strings when a non-empty default is provided
        if (String.isBlank(val) && String.isNotBlank(defaultVal)) return defaultVal;
        return val;
    }

    // Read a numeric logoSize from a header/column map. Defaults to 100, clamped to a
    // sane range (matches the slider in the builder).
    private static Integer readLogoSize(Map<String, Object> col) {
        if (col == null) return 100;
        Object raw = col.get('logoSize');
        if (raw == null) return 100;
        Integer n;
        try {
            if (raw instanceof Integer) n = (Integer) raw;
            else if (raw instanceof Decimal) n = ((Decimal) raw).intValue();
            else if (raw instanceof Double) n = ((Double) raw).intValue();
            else n = Integer.valueOf(String.valueOf(raw));
        } catch (Exception e) { return 100; }
        if (n < 30) n = 30;
        if (n > 500) n = 500;
        return n;
    }

    // Parse "200px" / "200" → 200. Returns null for "auto", "100%", blank, or unparseable.
    private static Integer pxToInt(String s) {
        if (String.isBlank(s)) return null;
        String t = s.trim().toLowerCase();
        if (t == 'auto' || t.endsWith('%')) return null;
        if (t.endsWith('px')) t = t.substring(0, t.length() - 2).trim();
        try { return Integer.valueOf(t); } catch (Exception e) { return null; }
    }

    /**
     * Simple string builder helper (Apex lacks java.lang.StringBuilder)
     */
    public class StringBuilder {
        private List<String> parts = new List<String>();

        public void append(String s) {
            if (s != null) parts.add(s);
        }

        public override String toString() {
            return String.join(parts, '');
        }
    }
}