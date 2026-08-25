// Managed by chezmoi. Keep this file to portable, deliberate overrides only.
// Do not add prefs.js state, profile IDs, account/sync data, extension records,
// personal URLs, site permissions, or timestamps. Replayed into prefs.js at
// every startup, so anything here wins over what the UI last wrote.

// Startup behavior.
user_pref("browser.startup.homepage", "about:newtab");
user_pref("browser.startup.page", 1);

// Custom UI support.
user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);

// Zen UI behavior.
user_pref("zen.urlbar.open-on-startup", false);
user_pref("zen.urlbar.replace-newtab", true);
user_pref("zen.view.compact.hide-tabbar", false);
user_pref("zen.view.sidebar-expanded", true);

// Zen chrome: square corners, no content inset, compact mode on at startup.
user_pref("zen.tabs.show-newtab-vertical", false);
user_pref("zen.theme.border-radius", 0);
user_pref("zen.theme.content-element-separation", 0);
user_pref("zen.view.compact.animate-sidebar", false);
user_pref("zen.view.compact.enable-at-startup", true);
user_pref("zen.view.compact.hide-toolbar", true);
user_pref("zen.view.compact.show-sidebar-and-toolbar-on-hover", false);
user_pref("zen.view.enable-loading-indicator", false);
user_pref("zen.view.show-newtab-button-top", false);
user_pref("zen.window-sync.enabled", false);
user_pref("zen.workspaces.separate-essentials", false);

// URL bar: no suggestions of any kind, so keystrokes never leave the browser.
user_pref("browser.urlbar.allowSearchSuggestionsForSimpleOrigins", false);
user_pref("browser.urlbar.recentsearches.featureGate", false);
user_pref("browser.urlbar.shortcuts.history", false);
user_pref("browser.urlbar.shortcuts.tabs", false);
user_pref("browser.urlbar.shortcuts.workspaces", false);
user_pref("browser.urlbar.showSearchSuggestionsFirst", false);
user_pref("browser.urlbar.suggest.addons", false);
user_pref("browser.urlbar.suggest.amp", false);
user_pref("browser.urlbar.suggest.calculator", false);
user_pref("browser.urlbar.suggest.clipboard", false);
user_pref("browser.urlbar.suggest.engines", false);
user_pref("browser.urlbar.suggest.history", false);
user_pref("browser.urlbar.suggest.importantDates", false);
user_pref("browser.urlbar.suggest.mdn", false);
user_pref("browser.urlbar.suggest.openpage", false);
user_pref("browser.urlbar.suggest.quickactions", false);
user_pref("browser.urlbar.suggest.realtimeOptIn", false);
user_pref("browser.urlbar.suggest.recentsearches", false);
user_pref("browser.urlbar.suggest.remotetab", false);
user_pref("browser.urlbar.suggest.searches", false);
user_pref("browser.urlbar.suggest.sports", false);
user_pref("browser.urlbar.suggest.topsites", false);
user_pref("browser.urlbar.suggest.trending", false);
user_pref("browser.urlbar.suggest.weather", false);
user_pref("browser.urlbar.suggest.wikipedia", false);
user_pref("browser.urlbar.suggest.yelp", false);
user_pref("browser.urlbar.suggest.yelpRealtime", false);

// New tab: empty, over the userContent.css wallpaper.
user_pref("browser.newtabpage.activity-stream.feeds.system.topsites", false);
user_pref("browser.newtabpage.activity-stream.improvesearch.topSiteSearchShortcuts", false);
user_pref("browser.newtabpage.activity-stream.section.highlights.includeBookmarks", false);
user_pref("browser.newtabpage.activity-stream.section.highlights.includeDownloads", false);
user_pref("browser.newtabpage.activity-stream.section.highlights.includeVisited", false);
user_pref("browser.newtabpage.activity-stream.showSearch", false);
user_pref("browser.topsites.useRemoteSetting", false);

// Privacy: clear history and form data at shutdown; keep cache and cookies.
user_pref("browser.contentblocking.category", "standard");
user_pref("privacy.clearHistory.formdata", true);
user_pref("privacy.clearOnShutdown_v2.cache", false);
user_pref("privacy.clearOnShutdown_v2.cookiesAndStorage", false);
user_pref("privacy.history.custom", true);
user_pref("privacy.sanitize.sanitizeOnShutdown", true);
user_pref("privacy.sanitize.timeSpan", 0);
user_pref("privacy.userContext.enabled", false);

// No speculative fetching or DNS resolution.
user_pref("network.dns.disablePrefetch", true);
user_pref("network.http.speculative-parallel-limit", 0);
user_pref("network.prefetch-next", false);

// Firefox's own sidebar (not Zen's): right-hand side, static.
user_pref("sidebar.animation.duration-ms", 100);
user_pref("sidebar.animation.enabled", false);
user_pref("sidebar.expandOnHover", false);
user_pref("sidebar.position_start", false);
user_pref("sidebar.visibility", "hide-on-close");

// Interface chrome and prompts.
user_pref("accessibility.typeaheadfind.flashBar", 0);
user_pref("browser.aboutConfig.showWarning", false);
user_pref("browser.display.document_color_use", 0);
user_pref("browser.toolbars.bookmarks.visibility", "always");
user_pref("browser.warnOnQuitShortcut", false);
user_pref("dom.forms.autocomplete.formautofill", true);
user_pref("layout.spellcheckDefault", 0);
user_pref("media.videocontrols.picture-in-picture.video-toggle.enabled", false);

// Pairs with the seeded handlers.json.
user_pref("browser.download.viewableInternally.typeWasRegistered.avif", true);
user_pref("browser.download.viewableInternally.typeWasRegistered.jxl", true);
user_pref("browser.download.viewableInternally.typeWasRegistered.webp", true);

// Locale and fonts -- the one language-revealing block; drop it as a unit for a
// locale-neutral profile. The sans-serif/serif pairings are transcribed from the
// live profile as-is, apparent swaps included.
user_pref("browser.translations.automaticallyPopup", false);
user_pref("browser.translations.neverTranslateLanguages", "ko");
user_pref("font.default.ko", "serif");
user_pref("font.language.group", "ko");
user_pref("font.name.monospace.ko", "JetBrainsMono Nerd Font");
user_pref("font.name.monospace.x-western", "JetBrainsMono Nerd Font");
user_pref("font.name.sans-serif.ko", "NanumGothic");
user_pref("font.name.sans-serif.x-western", "Noto Serif");
user_pref("font.name.serif.ko", "Noto Sans");
user_pref("font.name.serif.x-western", "Noto Serif");
