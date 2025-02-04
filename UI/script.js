let pubkey;
let relays = {};
let relayConnections = {}; // Store connections by URL
let selectedRelayUrl = null;
const profileReqId = "profile_req";
const messageReqId = "message_req";
const carouselSize = 30;
let messages = [];
let tagFilter = '';
let messageSource = 'relay';
let profiles = {}; // Store profiles by pubkey

// --- Utility Functions ---
function log(message) {
    const debugDiv = document.getElementById('debug');
    debugDiv.innerHTML += message + "<br>";
    console.log(message);
}

// --- Nostr Connect Functions ---
async function connectToNostr() {
    try {
        pubkey = await window.nostr.getPublicKey();
        log(`Connected as: ${pubkey}`);
        document.getElementById('status').innerText = `Connected as: ${pubkey}`;
        document.getElementById('sendMessageButton').disabled = false;

        await getRelays();
        createRelayButtons();
        connectToRelays();

    } catch (error) {
        log(`Connection failed: ${error.message}`);
        document.getElementById('status').innerText = `Connection failed: ${error.message}`;
    }
}

async function getRelays() {
    try {
        relays = await window.nostr.getRelays() || {}; // Initialize with empty object if null

        const defaultRelays = {
            "wss://relay.primal.net": { read: true, write: true },
            "wss://relay.damus.io": { read: true, write: true },
            "wss://relay.snort.social": { read: true, write: true },
            "wss://nostr.wine": { read: true, write: true }
            // Add more default relays here
        };

        // Merge default relays, but don't overwrite existing ones
        for (const relayUrl in defaultRelays) {
            if (!relays[relayUrl]) {
                relays[relayUrl] = defaultRelays[relayUrl];
            }
        }

        log(`Relays: ${JSON.stringify(relays)}`);

        const relaysList = document.getElementById('relaysList');
        relaysList.innerHTML = "";

        for (const relayUrl in relays) {
            const li = document.createElement("li");
            li.textContent = relayUrl;
            relaysList.appendChild(li);
        }

    } catch (error) {
        log(`Failed to get relays: ${error.message}`);
    }
}

function createRelayButtons() {
    const relaySelectionButtons = document.getElementById('relay-selection-buttons');
    relaySelectionButtons.innerHTML = '';

    for (const relayUrl in relays) {
        const button = document.createElement('button');
        button.textContent = relayUrl;
        button.dataset.relayUrl = relayUrl;

        button.addEventListener('click', () => {
            selectRelay(relayUrl);
        });

        relaySelectionButtons.appendChild(button);
    }
}

function selectRelay(relayUrl) {
    selectedRelayUrl = relayUrl;

    const buttons = document.querySelectorAll('#relay-selection-buttons button');
    buttons.forEach(btn => {
        btn.classList.remove('selected');
        if (btn.dataset.relayUrl === relayUrl) {
            btn.classList.add('selected');
        }
    });

    log(`Selected relay: ${selectedRelayUrl}`);
    fetchMessages();
    // Après avoir sélectionné le relay, refetch le profil pour ce relay spécifique.
    if (relayConnections[relayUrl] && relayConnections[relayUrl].readyState === WebSocket.OPEN) {
        fetchProfile(relayConnections[relayUrl]);
    }
}

function connectToRelays() {
    relayConnections = {};
    for (const relayUrl in relays) {
        if (relayConnections[relayUrl]) {
            log(`Already connected to relay: ${relayUrl}`);
            continue;
        }

        const ws = new WebSocket(relayUrl);
        relayConnections[relayUrl] = ws;
        ws.isReady = false;

        ws.onopen = () => {
            log(`Connected to relay: ${relayUrl}`);
            ws.isReady = true;
            //fetch profile on all relays
            // fetchProfile(ws);
            createMessageListener(ws);
            if (selectedRelayUrl === relayUrl) {
               log(`Selected relay to fetch message`);
                fetchMessages();
                fetchProfile(ws);
            }

        };

        ws.onerror = (error) => {
            log(`Error connecting to relay ${relayUrl}: ${error}`);
            ws.isReady = false;
        };

        ws.onclose = () => {
            log(`Disconnected from relay: ${relayUrl}`);
            ws.isReady = false;
            delete relayConnections[relayUrl];
        };


    }
}

function createMessageListener(ws) {
    ws.onmessage = (event) => {
        const data = JSON.parse(event.data);
        if (data[0] === "EVENT") {
            const eventData = data[2];
            // Only process kind 1 events (text messages)
            if (eventData.kind === 1) {
                processMessage(eventData, ws); // Pass 'ws' here
            }
        } else if (data[0] === "EOSE") {
            log(`EOSE received from relay: ${ws.url}`);
        }
    };
}

function fetchProfile(ws) {
    return new Promise((resolve, reject) => {
        const filter = {
            kinds: [0],
            authors: [pubkey]
        };

        log(`fetchProfile - Sending REQ for profile. pubkey: ${pubkey}, relay: ${ws.url}`);
        const reqMessage = JSON.stringify(["REQ", profileReqId, filter]);
        ws.send(reqMessage);
        log(`fetchProfile - Sent REQ: ${reqMessage}`);

        // Setup a temporary message handler for this profile request
        const profileMessageHandler = (event) => {
            const data = JSON.parse(event.data);
            log(`fetchProfile - Received message from relay ${ws.url}: ${JSON.stringify(data)}`);

            if (data[0] === "EVENT") {
                const eventData = data[2];
                log(`fetchProfile - Received EVENT: ${JSON.stringify(eventData)}`);

                if (eventData.kind === 0 && eventData.pubkey === pubkey) {
                    log(`fetchProfile - Found profile event for pubkey ${pubkey}`);
                    storeProfile(eventData);
                    displayMyProfile(profiles[eventData.pubkey])
                    resolve();  // Resolve the promise when the profile is successfully fetched
                } else {
                    log(`fetchProfile - Received EVENT but it's not a profile event or not for the correct pubkey.`);
                }
            } else if (data[0] === "EOSE") {
                log(`fetchProfile - Received EOSE from ${ws.url}`);
                resolve();  // Resolve the promise when EOSE is received
            } else {
                log(`fetchProfile - Received other message type: ${data[0]}`);
            }
        };

        const profileErrorHandler = (error) => {
            log(`fetchProfile - WebSocket error: ${error}`);
            reject(error);  // Reject the promise if there's an error
        };

        ws.addEventListener('message', profileMessageHandler);
        ws.addEventListener('error', profileErrorHandler);

        // Cleanup listeners after completion or error
        const cleanup = () => {
            ws.removeEventListener('message', profileMessageHandler);
            ws.removeEventListener('error', profileErrorHandler);
        };

        // Handle promise completion by cleaning up
        Promise.race([
            new Promise(resolve => setTimeout(resolve, 10000)),  // Timeout after 10 seconds
            new Promise((resolve, reject) => {
                ws.addEventListener('close', () => {
                    reject(new Error('WebSocket closed'));
                });
            })
        ]).finally(cleanup);
    });
}

function storeProfile(eventData) {
    log(`storeProfile - Processing eventData: ${JSON.stringify(eventData)}`);
    try {
        const profile = JSON.parse(eventData.content);
        profiles[eventData.pubkey] = profile; // Stocker le profil par clé publique
        log(`Profile stored for ${eventData.pubkey}: ${JSON.stringify(profile)}`);
        if (eventData.pubkey === pubkey) {
            displayMyProfile(profile);
        }
    } catch (error) {
        log(`Failed to parse profile: ${error.message}, content: ${eventData.content}`);
    }
}

function displayMyProfile(profile) {
    const avatarUrl = profile.picture;
    const name = profile.name;
    const about = profile.about;

    log(`displayMyProfile - avatarUrl: ${avatarUrl}`);
    log(`displayMyProfile - name: ${name}`);
    log(`displayMyProfile - about: ${about}`);

    if (avatarUrl) {
        document.getElementById('profileAvatar').src = avatarUrl;
    } else {
        document.getElementById('profileAvatar').src = 'default_avatar.png'; // Use a default avatar
    }
    if (name) {
        document.getElementById('profileName').textContent = name;
    } else {
        document.getElementById('profileName').textContent = 'Unknown User';
    }
    if (about) {
        document.getElementById('profileAbout').textContent = about;
    } else {
        document.getElementById('profileAbout').textContent = 'No description available.';
    }
}

async function sendMessage() {
    const message = document.getElementById('messageInput').value;

    if (!message) {
        alert("Please enter a message");
        return;
    }

    const event = {
        kind: 1,
        content: message,
        tags: [],
        created_at: Math.floor(Date.now() / 1000)
    };

    try {
        const signedEvent = await window.nostr.signEvent(event);

        for (const relayUrl in relayConnections) {
            const ws = relayConnections[relayUrl];
            if (ws.readyState === WebSocket.OPEN) {
                ws.send(JSON.stringify(["EVENT", signedEvent]));
                log(`Sent message to relay: ${ws.url}`);
            } else {
                log(`Relay ${relayUrl} is not open, cannot send message.`);
            }
        }

    } catch (error) {
        log(`Error sending message: ${error.message}`);
        alert(`Error sending message: ${error.message}`);
    }
}

function fetchMessages() {
    messages = [];
    updateCarousel();

    if (!selectedRelayUrl) {
        log("No relay selected, cannot fetch messages.");
        return;
    }

    let ws = relayConnections[selectedRelayUrl];
    if (!ws || !ws.isReady) {
        log(`Selected relay ${selectedRelayUrl} not connected or not ready.`);
        return;
    }

    const filter = {
        kinds: [1],
        limit: carouselSize
    };

    if (messageSource === 'own') {
        filter.authors = [pubkey];
    } else if (messageSource === 'friends') {
        // Implement friend logic to fetch all friends
        const friendPubkeys = Object.keys(profiles).filter(key => key !== pubkey);
        if (friendPubkeys.length > 0) {
            filter.authors = friendPubkeys;
        } else {
            // If no friends, display a message
            displayNoFriendsMessage();
            return;
        }
    }

    log(`Fetching messages from ${selectedRelayUrl} with filter: ${JSON.stringify(filter)}`);
    ws.send(JSON.stringify(["REQ", messageReqId, filter]));
}

function processMessage(eventData, ws) { // Receive 'ws' here
    log(`processMessage - Processing message ${eventData.id} from ${ws.url}`);

    if (!tagFilter || eventData.tags.some(tag => tag[0] === 'topic' && tag[1] === tagFilter)) {
        switch (messageSource) {
            case 'own':
                if (eventData.pubkey === pubkey) {
                    messages.push(eventData);
                }
                break;
            case 'friends':
                // Filter messages based on pubkey matching a friend
                const friendPubkeys = Object.keys(profiles).filter(key => key !== pubkey);
                if (friendPubkeys.includes(eventData.pubkey)) {
                    messages.push(eventData);
                }
                break;
            case 'relay':
                messages.push(eventData);
                break;
        }

        if (messages.length > carouselSize) {
            messages = messages.slice(messages.length - carouselSize);
        }

        updateCarousel(ws); // Pass 'ws' here
    } else {
        log(`processMessage - Message ${eventData.id} filtered out due to tagFilter: ${tagFilter}`);
    }
}
function displayNoFriendsMessage() {
    const carouselTrack = document.getElementById('messageCarousel');
    carouselTrack.innerHTML = '<li>No friends followed or no friends have profile</li>';
}
// --- Carousel Functions ---
function updateCarousel(ws) { // Receive 'ws' here
    const carouselTrack = document.getElementById('messageCarousel');
    carouselTrack.innerHTML = '';

    if (messages.length === 0) {
        carouselTrack.innerHTML = '<li>No messages to display.</li>';
        return;
    }

    messages.forEach(message => {
        const li = document.createElement("li");
        li.classList.add("carousel-slide");

        // Afficher le profil (avatar et nom)
        const profile = profiles[message.pubkey];
        let profileDisplay = '';
        if (profile) {
            profileDisplay = `<img src="${profile.picture || 'default_avatar.png'}" alt="Avatar" style="width: 30px; height: 30px; border-radius: 50%; vertical-align: middle;"> ${profile.name || 'Unknown User'}: `;
        } else {
            profileDisplay = `<img src="default_avatar.png" alt="Avatar" style="width: 30px; height: 30px; border-radius: 50%; vertical-align: middle;"> Unknown User: `;
        }

        const imetaTag = message.tags.find(tag => tag[0] === 'imeta');

        let messageContent = '';

        if (imetaTag) {
            const imetaData = {};
            imetaTag.forEach(item => {
                const parts = item.split(' ');
                if (parts.length === 2) {
                    const key = parts[0];
                    const value = parts[1];
                    imetaData[key] = value;
                }
            });

            messageContent = '<strong>Media Info:</strong><br>';
            messageContent += `URL: <a href="${imetaData.url}" target="_blank">${imetaData.url}</a><br>`;
            messageContent += `Type: ${imetaData.m || 'N/A'}<br>`;
            messageContent += `Dimensions: ${imetaData.dim || 'N/A'}<br>`;
            messageContent += `Hash: ${imetaData.ox || 'N/A'}`;

            if (imetaData.m && imetaData.url) {
                if (imetaData.m.startsWith('image/')) {
                    messageContent += `<br><img src="${imetaData.url}" alt="Media Preview" style="max-width: 100%; max-height: 150px;">`;
                } else if (imetaData.m.startsWith('video/')) {
                    messageContent += `<br><video src="${imetaData.url}" controls style="max-width: 100%; max-height: 150px;"></video>`;
                }
            }
        } else {
            messageContent = message.content;
        }

        // Afficher l'URL du relay
        const relayUrl = ws.url; // Assuming 'ws' is the WebSocket connection
        li.innerHTML = `${profileDisplay} ${messageContent} <br><small>Source: ${relayUrl}</small>`;

        // Ajouter des boutons d'interaction (exemple)
        li.innerHTML += `<br><button onclick="replyToMessage('${message.id}')">Reply</button> <button onclick="likeMessage('${message.id}')">Like</button>`;

        carouselTrack.appendChild(li);
    });

    // Carousel navigation (minimal)
    const track = document.querySelector('.carousel-track');
    const firstSlide = document.querySelector('.carousel-slide');
    const slideWidth = firstSlide ? firstSlide.offsetWidth : 0;

    if (!firstSlide) {
        console.warn('No carousel slides found. The carousel may not be initialized properly.');
        return; // Exit the function if there are no slides
    }
    track.style.transform = `translateX(0)`;
}

// --- Event Listeners ---
document.addEventListener('DOMContentLoaded', () => {
    document.getElementById('connectButton').addEventListener('click', connectToNostr);
    document.getElementById('sendMessageButton').addEventListener('click', sendMessage);

    document.querySelectorAll('.carousel-button').forEach(button => {
        button.addEventListener('click', () => {
            const track = document.querySelector('.carousel-track');
            const firstSlide = document.querySelector('.carousel-slide');
            const slideWidth = firstSlide ? firstSlide.offsetWidth : 0;

            if (!firstSlide) {
                console.warn('No carousel slides found. The carousel may not be initialized properly.');
                return; // Exit the function if there are no slides
            }
            const direction = button.dataset.direction;

            if (direction === 'next') {
                track.style.transform = `translateX(-${slideWidth}px)`;
                track.appendChild(track.firstElementChild);
                track.style.transition = 'none';
                track.style.transform = `translateX(0)`;
                setTimeout(() => track.style.transition = 'transform 0.5s ease-in-out', 0);
            } else {
                track.insertBefore(track.lastElementChild, track.firstElementChild);
                track.style.transition = 'none';
                track.style.transform = `translateX(-${slideWidth}px)`;
                setTimeout(() => {
                    track.style.transition = 'transform 0.5s ease-in-out';
                    track.style.transform = `translateX(0)`;
                }, 0);
            }
        });
    });

    document.getElementById('messageSource').addEventListener('change', (event) => {
        messageSource = event.target.value;
        log(`Message source changed to: ${messageSource}`);
        fetchMessages();
    });

    document.getElementById('tagFilter').addEventListener('input', (event) => {
        tagFilter = event.target.value;
        log(`Tag filter changed to: ${tagFilter}`);
        fetchMessages();
    });

    log("App started (no backend)");
});

// Placeholder functions for interaction buttons (implement later)
function replyToMessage(messageId) {
    log(`Replying to message: ${messageId}`);
    // Implement reply logic (requires creating a new event)
}

function likeMessage(messageId) {
    log(`Liking message: ${messageId}`);
    // Implement like logic (requires creating a new event)
}
