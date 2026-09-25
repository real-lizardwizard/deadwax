/*
 * The project was called jimbrainz until v0.6.21, and every preference it saved in the
 * browser is under a `jimbrainz-` key: panel sizes, release columns, the library's fields,
 * sort and pane width, the log's open state, the settings tab's preferences. Renaming the
 * keys without carrying them across would quietly reset all of that for everyone on upgrade.
 *
 * A CLASSIC script in <head>, not a module, and that is load-bearing: module scripts run in
 * document order after parsing, and resize.js reads its key before main.js does, so this has
 * to have finished before any module starts. A classic script without `defer` runs right here.
 *
 * A key already saved under the new name wins - it can only have been written by deadwax
 * itself, and is newer. The old key is removed either way, so this does nothing after the
 * first load. Wrapped whole, because localStorage throws rather than returning null in some
 * private windows, and a failed migration must never stop the page from loading.
 */
(function () {
    try {
        var OLD = 'jimbrainz-';
        var NEW = 'deadwax-';
        var keys = [];
        for (var i = 0; i < localStorage.length; i++) {
            var key = localStorage.key(i);
            if (key && key.indexOf(OLD) === 0) keys.push(key);
        }
        keys.forEach(function (key) {
            var renamed = NEW + key.slice(OLD.length);
            if (localStorage.getItem(renamed) === null) {
                localStorage.setItem(renamed, localStorage.getItem(key));
            }
            localStorage.removeItem(key);
        });
    } catch (e) {
        /* nothing saved is lost by skipping this - the old keys are left where they were */
    }
})();
