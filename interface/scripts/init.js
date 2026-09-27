/*
 * Page start-up: the event log's stream, and the two connection pills.
 *
 * The pings wait for the stream to OPEN, not for a fixed pause (v0.9.21). The MusicBrainz ping
 * writes "Connection successful" to the log, and the stream has no history, so a line logged
 * before this page is listening is gone. A 100ms sleep was a guess at that, too long on a LAN
 * and too short on a slow link. The wait is capped so a stream that never opens can't hold the
 * pills on "loading..." - they are drawn as pending first either way.
 */
const STREAM_OPEN_WAIT_MS = 2000;

//? what a ping can answer, and the code a pill shows for it
async function checkPing(name, url) {
    try {
        const response = await fetch(url);
        const answer = response.ok ? await response.json() : null;
        const status = String(answer?.status || '').toLowerCase();

        if (status === 'ok') setConnection(name, 'ok', 'connected');
        else if (status === 'failed') setConnection(name, 'failed', answer.code);
        else setConnection(name, 'failed', answer ? 'UNEXPECTED' : 'CONNECTION_ERROR');
    }
    catch {
        setConnection(name, 'failed', 'CONNECTION_ERROR');
    }
}

//? one pill per service, made on first use and updated in place after
function setConnection(name, status, code) {
    let pill = document.querySelector(`.connection-item[data-connection="${name}"]`);

    if (!pill) {
        pill = document.createElement('div');
        pill.className = 'connection-item';
        pill.dataset.connection = name;
        //? the status dot is an empty span with a width; its class carries the brand colour
        pill.innerHTML = `
            <div class="connection-info">
                <span class="connection-info-name ${name}" aria-hidden="true"></span>
                <h4 class="connection-info-line text white">${name}</h4>
                <h4 class="connection-info-code text"></h4>
            </div>`;
        document.getElementById('general-connection-status').appendChild(pill);
    }

    pill.querySelector('.connection-info').className = `connection-info ${status}`;
    //? codes come from slskd's own state and are quoted back, so text, never markup
    pill.querySelector('.connection-info-code').textContent = code || '';
}


/*
 * One line of the event log. Built as TEXT (v0.9.21): the log quotes MusicBrainz titles, Soulseek
 * queries and folder paths, all typed by other people, and this used to set them as innerHTML -
 * an album called `<img onerror=...>` would have run in the page.
 */
function eventLine(eventType, content, src) {
    const item = document.createElement('div');
    item.className = 'event-item';

    const first = document.createElement('div');
    first.className = 'first-row';
    first.append(
        line('h5', `text default event-type ${eventType}`, eventType),
        line('h5', 'text white event-time', `[${new Date().toTimeString().slice(0, 8)}]\u00a0\u00a0`),
    );
    if (src) first.append(line('h5', `text default-secondary event-src ${src.toLowerCase()}`, src));

    const second = document.createElement('div');
    second.className = 'second-row';
    second.append(
        line('h4', 'text event-content-indent', '└─╲'),
        line('h5', 'text default-secondary event-content', content),
    );

    item.append(first, second);
    return item;
}

function line(tag, className, text) {
    const element = document.createElement(tag);
    element.className = className;
    element.textContent = text;
    return element;
}

function logEvent(eventType, content, src) {
    const item = eventLine(eventType, content, src);
    document.getElementById('logs-scrollable').prepend(item);
    return item;
}

const STREAM_LOST = 'Failed to connect to backend';


let eventSource = null;

function openEventStream() {
    eventSource = new EventSource('/deadwax/interface_logs/interface_logs');

    eventSource.onerror = () => {
        //? EventSource retries every few seconds while the server is down: one line, not a column
        const previous = logEvent('ERROR', STREAM_LOST).nextElementSibling;
        if (previous?.querySelector('.event-content')?.textContent === STREAM_LOST) previous.remove();
    };
    eventSource.onmessage = (event) => {
        const data = JSON.parse(event.data);
        logEvent(data.event_type, data.event_content, data.src);
    };

    return new Promise((resolve) => {
        eventSource.addEventListener('open', resolve, { once: true });
        eventSource.addEventListener('error', resolve, { once: true });
        setTimeout(resolve, STREAM_OPEN_WAIT_MS);
    });
}

export async function init() {
    setConnection('musicbrainz', 'pending', 'loading...');
    setConnection('slskd', 'pending', 'loading...');

    await openEventStream();

    await Promise.all([
        checkPing('musicbrainz', '/deadwax/search_musicbrainz/ping'),
        checkPing('slskd', '/deadwax/monitor_slskd/ping'),
    ]);
}

window.addEventListener('beforeunload', () => {
    if (eventSource) {
        eventSource.close();
    }
});
