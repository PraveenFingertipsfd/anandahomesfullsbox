import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getTemplatesForRecord from '@salesforce/apex/DocumentViewerController.getTemplatesForRecord';
import getVfPagesForRecord from '@salesforce/apex/DocumentViewerController.getVfPagesForRecord';
import getVfPageContentAsWord from '@salesforce/apex/DocumentViewerController.getVfPageContentAsWord';
import getVfPageContentAsPdf from '@salesforce/apex/DocumentViewerController.getVfPageContentAsPdf';

export default class DocumentViewer extends NavigationMixin(LightningElement) {
    @api recordId;
    @api objectApiName;
    @api cardTitle = 'Documents';
    @api hideDescription = false;
    @api layout = 'list'; // list | grid | compact
    @api hideVfPages = false; // optionally hide the VF Pages section

    @track templates = [];
    @track vfPages = [];
    @track isLoading = false;
    @track error;
    @track vfError;
    @track isWordGenerating = false;

    // Preview state
    @track showPreview = false;
    @track previewUrl = '';        // HTML render shown in the iframe
    @track previewPdfUrl = '';     // PDF URL for the download button (blank for VF pages)
    @track previewDocName = '';
    @track previewIsPdf = false;   // true = document template preview (show PDF download)

    connectedCallback() {
        this.loadTemplates();
        this.loadVfPages();
    }

    loadTemplates() {
        if (!this.recordId) return;
        this.isLoading = true;
        this.error = undefined;
        getTemplatesForRecord({ recordId: this.recordId, objectApiName: this.objectApiName || '' })
            .then(result => {
                this.templates = (result || []).map((t, i) => ({
                    ...t,
                    _key: 'doc-' + i,
                    _hasDescription: !this.hideDescription && !!t.description
                }));
            })
            .catch(err => {
                this.error = this._getError(err);
                this.templates = [];
            })
            .finally(() => { this.isLoading = false; });
    }

    loadVfPages() {
        if (!this.recordId || this.hideVfPages) return;
        this.vfError = undefined;
        getVfPagesForRecord({ recordId: this.recordId, objectApiName: this.objectApiName || '' })
            .then(result => {
                this.vfPages = (result || []).map((p, i) => ({
                    ...p,
                    _key: 'vf-' + i,
                    _hasDescription: !this.hideDescription && !!p.description
                }));
            })
            .catch(err => {
                this.vfError = this._getError(err);
                this.vfPages = [];
            });
    }

    // ==================== COMPUTED ====================

    get hasTemplates() {
        return this.templates && this.templates.length > 0;
    }

    get templateCount() {
        return this.templates ? this.templates.length : 0;
    }

    get pluralSuffix() {
        return this.templateCount === 1 ? '' : 's';
    }

    get hasVfPages() {
        return !this.hideVfPages && this.vfPages && this.vfPages.length > 0;
    }

    get vfPageCount() {
        return this.vfPages ? this.vfPages.length : 0;
    }

    get vfPluralSuffix() {
        return this.vfPageCount === 1 ? '' : 's';
    }

    get showVfSection() {
        return !this.hideVfPages && (this.hasVfPages || this.vfError);
    }

    get hasNoContent() {
        return !this.hasTemplates && !this.hasVfPages;
    }

    get isListLayout() { return this.layout === 'list'; }
    get isGridLayout() { return this.layout === 'grid'; }
    get isCompactLayout() { return this.layout === 'compact'; }

    get containerClass() {
        if (this.layout === 'grid') return 'doc-grid';
        if (this.layout === 'compact') return 'doc-compact';
        return 'doc-list';
    }

    // ==================== HANDLERS: DOCUMENT TEMPLATES ====================

    handlePreviewPdf(event) {
        event.stopPropagation();
        const url = event.currentTarget.dataset.url;
        const name = event.currentTarget.dataset.name || 'Document';
        if (url) {
            this.previewUrl = url;
            this.previewPdfUrl = event.currentTarget.dataset.pdf || url;
            this.previewDocName = name;
            this.previewIsPdf = true;
            this.showPreview = true;
        }
    }

    handleDownloadPdf(event) {
        event.stopPropagation();
        const url = event.currentTarget.dataset.url;
        if (url) {
            window.open(url, '_blank');
        }
    }

    handleViewWord(event) {
        event.stopPropagation();
        const url = event.currentTarget.dataset.url;
        if (url) {
            window.open(url, '_blank');
        }
    }

    handleDownloadWord(event) {
        event.stopPropagation();
        const url = event.currentTarget.dataset.url;
        if (url) {
            window.open(url, '_blank');
        }
    }

    handleSendEmail(event) {
        event.stopPropagation();
        const templateId = event.currentTarget.dataset.id;
        const name = event.currentTarget.dataset.name || 'Document';
        const sender = this.template.querySelector('c-email-sender');
        if (sender) {
            sender.openForDocument(templateId, name);
        }
    }

    // ==================== HANDLERS: VF PAGES ====================

    /** Preview a related VF page inside the same preview panel */
    handlePreviewVfPage(event) {
        event.stopPropagation();
        const url = event.currentTarget.dataset.url;
        const name = event.currentTarget.dataset.name || 'Page';
        if (url) {
            this.previewUrl = url;
            this.previewPdfUrl = '';
            this.previewDocName = name;
            this.previewIsPdf = false;
            this.showPreview = true;
        }
    }

    /**
     * Download the VF page as a Word (.doc) file.
     * Apex fetches the page's rendered HTML server-side (getContent) and
     * returns it base64-encoded; we save it with a .doc extension, which
     * Word opens natively.
     */
    handleWordVfPage(event) {
        event.stopPropagation();
        const pageName = event.currentTarget.dataset.page;
        const label = event.currentTarget.dataset.name || pageName || 'Page';
        if (!pageName || this.isWordGenerating) return;

        this.isWordGenerating = true;
        getVfPageContentAsWord({ pageName, recordId: this.recordId })
            .then(result => {
                const base64 = result && result.base64;
                if (!base64) {
                    throw new Error('The page returned no content');
                }
                // Pages that render as HTML download as .doc (Word opens them).
                // Pages defined with renderAs="pdf" can't be converted to Word,
                // so they download as a valid .pdf instead.
                const isPdf = result.fileType === 'pdf';
                this._downloadBase64(
                    base64, label,
                    isPdf ? '.pdf' : '.doc',
                    isPdf ? 'application/pdf' : 'text/html' // both LWS-allowed
                );
            })
            .catch(err => {
                this.vfError = 'Word download failed: ' + this._getError(err);
            })
            .finally(() => {
                this.isWordGenerating = false;
            });
    }

    /**
     * Download the VF page rendered as a PDF.
     * getContentAsPDF() on the server forces PDF rendering, so this works
     * for every page — including ones that normally render as HTML.
     */
    handlePdfVfPage(event) {
        event.stopPropagation();
        const pageName = event.currentTarget.dataset.page;
        const label = event.currentTarget.dataset.name || pageName || 'Page';
        if (!pageName || this.isWordGenerating) return;

        this.isWordGenerating = true;
        getVfPageContentAsPdf({ pageName, recordId: this.recordId })
            .then(base64 => {
                if (!base64) {
                    throw new Error('The page returned no content');
                }
                this._downloadBase64(base64, label, '.pdf', 'application/pdf');
            })
            .catch(err => {
                this.vfError = 'PDF download failed: ' + this._getError(err);
            })
            .finally(() => {
                this.isWordGenerating = false;
            });
    }

    /**
     * Open the email composer for this VF page — same pattern as the
     * template rows' handleSendEmail, just calling openForVfPage so the
     * page (not a designer template) gets pinned as the PDF attachment.
     */
    handleEmailVfPage(event) {
        event.stopPropagation();
        const pageName = event.currentTarget.dataset.page;
        const label = event.currentTarget.dataset.name || pageName || 'Page';
        const sender = this.template.querySelector('c-email-sender');
        if (sender) {
            try {
                sender.openForVfPage(pageName, label);
            } catch (e) {
                // Deployed emailSender bundle is outdated (no openForVfPage yet)
                this.vfError = 'Please deploy the updated emailSender component (openForVfPage missing).';
            }
        }
    }

    /** Open the VF page in a new browser tab */
    handleOpenVfPage(event) {
        event.stopPropagation();
        const url = event.currentTarget.dataset.url;
        if (url) {
            window.open(url, '_blank');
        }
    }

    // ==================== SHARED ====================

    handleClosePreview() {
        this.showPreview = false;
        this.previewUrl = '';
        this.previewPdfUrl = '';
        this.previewDocName = '';
        this.previewIsPdf = false;
    }

    handleRefresh() {
        this.showPreview = false;
        this.loadTemplates();
        this.loadVfPages();
    }

    // ==================== HELPERS ====================

    /** Download base64 content as a file (LWS-safe MIME types only) */
    _downloadBase64(base64, label, ext, mime) {
        const byteChars = atob(base64);
        const byteNumbers = new Array(byteChars.length);
        for (let i = 0; i < byteChars.length; i++) {
            byteNumbers[i] = byteChars.charCodeAt(i);
        }
        const fileName = label.replace(/[\\/:*?"<>|]/g, '_') + ext;

        let href;
        let revoke = false;
        try {
            const blob = new Blob([new Uint8Array(byteNumbers)], { type: mime });
            href = URL.createObjectURL(blob);
            revoke = true;
        } catch (blobErr) {
            // Fallback if Blob creation is blocked: data URI
            href = 'data:' + mime + ';base64,' + base64;
        }

        const link = document.createElement('a');
        link.href = href;
        link.download = fileName;
        link.click();
        if (revoke) {
            URL.revokeObjectURL(href);
        }
    }

    _getError(error) {
        if (Array.isArray(error?.body)) return error.body.map(e => e.message).join(', ');
        if (error?.body?.message) return error.body.message;
        if (error?.message) return error.message;
        return 'Unknown error';
    }
}