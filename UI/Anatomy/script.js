let pubkey;
let relays = {};
let relayConnections = {};
let selectedRelayUrl = null;
const profileReqId = "profile_req";
const eventReqId = "event_req";
let profiles = {};

// --- Utility Functions ---
function log(message) {
    const debugDiv = document.getElementById('debug');
    debugDiv.innerHTML += message + "<br>";
    console.log(message);
}

function sanitizeInput(input) {
    return DOMPurify.sanitize(input);
}

function displayEventDetails(event) {
    const eventDetailsDiv = document.getElementById('eventDetails');
    if (!event) {
        eventDetailsDiv.innerText = "Event not found or invalid";
        return;
    }

    let details = `<strong>ID:</strong> ${event.id}<br>`;
    details += `<strong>Pubkey:</strong> ${event.pubkey}<br>`;
    details += `<strong>Created At:</strong> ${new Date(event.created_at * 1000).toLocaleString()}<br>`;
    details += `<strong>Kind:</strong> ${event.kind}<br>`;
    details += `<strong>Tags:</strong><br><pre><code class="language-json">${JSON.stringify(event.tags, null, 2)}</code></pre><br>`;
    details += `<strong>Content:</strong><br><pre><code class="language-json">${event.content}</code></pre><br>`;
    details += `<strong>Signature:</strong> ${event.sig}<br>`;
      hljs.highlightAll();
    eventDetailsDiv.innerHTML = details;
}
function displayProfileDetails(profile) {
    const profileDetailsDiv = document.getElementById('profileDetails');
    if (!profile) {
        profileDetailsDiv.innerText = "Profile not found or invalid, or invalid profile data";
        return;
    }

    document.getElementById('profileName').value = profile.name || "";
    document.getElementById('profileAbout').value = profile.about || "";
    document.getElementById('profilePicture').value = profile.picture || "";
    document.getElementById('profileNip05').value = profile.nip05 || "";
    document.getElementById('profileLud16').value = profile.lud16 || "";
    /*let details = `<strong>Name:</strong> ${profile.name || 'N/A'}<br>`;
    details += `<strong>About:</strong> ${profile.about || 'N/A'}<br>`;
    details += `<strong>Picture:</strong> <img src="${profile.picture || 'default_avatar.png'}" alt="Avatar" style="max-width: 100px;"><br>`;
    details += `<strong>NIP-05:</strong> ${profile.nip05 || 'N/A'}<br>`;
    details += `<strong>lud16:</strong> ${profile.lud16 || 'N/A'}<br>`;

    profileDetailsDiv.innerHTML = details;*/
    // Enable the inputs
    document.getElementById('profileName').disabled = false;
    document.getElementById('profileAbout').disabled = false;
    document.getElementById('profilePicture').disabled = false;
    document.getElementById('profileNip05').disabled = false;
    document.getElementById('profileLud16').disabled = false;
}

function clearProfileDisplay() {
    document.getElementById('profileName').value =  "";
    document.getElementById('profileAbout').value =  "";
    document.getElementById('profilePicture').value =  "";
    document.getElementById('profileNip05').value =  "";
    document.getElementById('profileLud16').value =  "";
}

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
    });
}
// --- Nostr Connect Functions ---
async function connectToNostr() {
    try {
        pubkey = await window.nostr.getPublicKey();
        log(`Connected as: ${pubkey}`);
        document.getElementById('status').innerText = `Connected as: ${pubkey}`;
        document.getElementById('editProfileButton').disabled = false;
        document.getElementById('profilePubKey').value = pubkey;

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
    relays = await window.nostr.getRelays() || {};

    const defaultRelays = {
      "wss://relay.primal.net": {
        read: true,
        write: true
      },
      "wss://relay.damus.io": {
        read: true,
        write: true
      },
      "wss://relay.snort.social": {
        read: true,
        write: true
      },
      "wss://nostr.wine": {
        read: true,
        write: true
      }
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
    //relaysList.innerHTML = "";

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
    //fetchMessages();
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

function displayEventList(events) {
    const eventListDiv = document.getElementById('eventList');
    eventListDiv.innerHTML = ''; // Clear previous list

    if (!events || events.length === 0) {
        eventListDiv.innerText = "No events found.";
        return;
    }

    const ul = document.createElement('ul');
    events.forEach(event => {
        const li = document.createElement('li');
        li.classList.add('event-item');

        const summary = document.createElement('div');
        summary.classList.add('event-summary');
        summary.textContent = `Kind: ${event.kind}, Pubkey: ${event.pubkey}, Created: ${new Date(event.created_at * 1000).toLocaleString()}`;
        li.appendChild(summary);

        const detailsButton = document.createElement('button');
        detailsButton.textContent = 'Show Details';
        detailsButton.addEventListener('click', () => {
            toggleEventDetails(li, event);
        });
        li.appendChild(detailsButton);

        const detailsDiv = document.createElement('div');
        detailsDiv.classList.add('event-details');
        detailsDiv.style.display = 'none'; // Initially hidden
        li.appendChild(detailsDiv);

        ul.appendChild(li);
    });

    eventListDiv.appendChild(ul);
}

function toggleEventDetails(listItem, event) {
    const detailsDiv = listItem.querySelector('.event-details');
    const detailsButton = listItem.querySelector('button');

    if (detailsDiv.style.display === 'none') {
        // Display details
        let details = `<strong>ID:</strong> ${event.id}<br>`;
        details += `<strong>Pubkey:</strong> ${event.pubkey}<br>`;
        details += `<strong>Created At:</strong> ${new Date(event.created_at * 1000).toLocaleString()}<br>`;
        details += `<strong>Kind:</strong> ${event.kind}<br>`;
        details += `<strong>Tags:</strong><br><pre><code class="language-json">${JSON.stringify(event.tags, null, 2)}</code></pre><br>`;
        details += `<strong>Content:</strong><br><pre><code class="language-json">${sanitizeInput(event.content)}</code></pre><br>`;
        details += `<strong>Signature:</strong> ${event.sig}<br>`;

        detailsDiv.innerHTML = details;
        hljs.highlightAll();
        detailsDiv.style.display = 'block';
        detailsButton.textContent = 'Hide Details';

    } else {
        // Hide details
        detailsDiv.style.display = 'none';
        detailsButton.textContent = 'Show Details';
    }
}

async function fetchEvent() {
    const eventId = document.getElementById('eventId').value;
    const eventKind = document.getElementById('eventKind').value; // Get the event kind from the input field

    if (!eventId && !eventKind) {
        alert("Please enter either an Event ID or an Event Kind");
        return;
    }

    if (!selectedRelayUrl) {
        alert("Please select a relay first.");
        return;
    }

    const ws = relayConnections[selectedRelayUrl];
    if (!ws || !ws.isReady) {
        alert(`Not connected to relay ${selectedRelayUrl} or relay not ready.`);
        return;
    }

    let filter = {};
    if (eventId) {
        filter.ids = [eventId];
    }
    if (eventKind) {
        filter.kinds = [parseInt(eventKind)]; // Parse the event kind as an integer
    }

    log(`Fetching event with filter: ${JSON.stringify(filter)} from ${selectedRelayUrl}`);
    ws.send(JSON.stringify(["REQ", eventReqId, filter]));

    let events = []; // Store the events

    // Listener pour la requête d'événement spécifique
    ws.onmessage = (event) => {
        const data = JSON.parse(event.data);
        if (data[0] === "EVENT") {
            const eventData = data[2];
             events.push(eventData); // Store the event for display

        } else if (data[0] === "EOSE") {
            log(`EOSE: ${JSON.stringify(data)}`);
              displayEventList(events); // Display all the events
             events = [];
        }
    };
}

// --- Profile Management Functions ---
async function fetchProfile() {
    const profilePubKey = document.getElementById('profilePubKey').value;
    if (!profilePubKey) {
        alert("Please enter a Pubkey");
        return;
    }

    if (!selectedRelayUrl) {
        alert("Please select a relay first.");
        return;
    }

    const ws = relayConnections[selectedRelayUrl];
    if (!ws || !ws.isReady) {
        alert(`Not connected to relay ${selectedRelayUrl} or relay not ready.`);
        return;
    }

    const filter = {
        kinds: [0],
        authors: [profilePubKey]
    };
    log(`Fetching profile ${profilePubKey} from ${selectedRelayUrl}`);
    ws.send(JSON.stringify(["REQ", profileReqId, filter]));

    // Listener pour la requête de profil spécifique
    ws.onmessage = (event) => {
        const data = JSON.parse(event.data);
        if (data[0] === "EVENT") {
            const eventData = data[2];
            log(`fetchProfile - Received EVENT: ${JSON.stringify(eventData)}`);
            if (eventData.kind === 0 && eventData.pubkey === profilePubKey) {
                storeProfile(eventData);
                clearProfileDisplay();
                displayProfileDetails(JSON.parse(eventData.content));
            }
        }
    };
}
function storeProfile(eventData) {
    log(`storeProfile - Processing eventData: ${JSON.stringify(eventData)}`);
    try {
        const profile = JSON.parse(eventData.content);
        profiles[eventData.pubkey] = profile; // Stocker le profil par clé publique
        log(`Profile stored for ${eventData.pubkey}: ${JSON.stringify(profile)}`);
    } catch (error) {
        log(`Failed to parse profile: ${error.message}, content: ${eventData.content}`);
    }
}

async function editProfile() {
 const profilePubKey = document.getElementById('profilePubKey').value;
  if (!profilePubKey) {
    alert("Please enter a Pubkey");
    return;
  }

    // Fetch values from the input fields
  const name = sanitizeInput(document.getElementById('profileName').value);
  const about = sanitizeInput(document.getElementById('profileAbout').value);
  const picture = sanitizeInput(document.getElementById('profilePicture').value);
  const nip05 = sanitizeInput(document.getElementById('profileNip05').value);
  const lud16 = sanitizeInput(document.getElementById('profileLud16').value);

    if (!selectedRelayUrl) {
        alert("Please select a relay first.");
        return;
    }
    const ws = relayConnections[selectedRelayUrl];
    if (!ws || !ws.isReady) {
        log(`not connected to relai or relai not ready.`);
        alert(`Not connected to relay ${selectedRelayUrl} or relay not ready.`);
        return;
    }

// Create the new profile object
  const newProfile = {
        name: name,
        about: about,
        picture: picture,
        nip05: nip05,
        lud16: lud16
    };
  const profileEvent = {
        kind: 0,
        content: JSON.stringify(newProfile),
        tags: [],
        created_at: Math.floor(Date.now() / 1000)
    };

  try {
    const signedEvent = await window.nostr.signEvent(profileEvent);
    if (!signedEvent) {
      log(`Profile signing failed.  Possible nostr connect error`);
      alert(`Profile signing failed.  Possible nostr connect error`);
      return;
    }
    log(`Signed event OK event: ${JSON.stringify(signedEvent)}`);
    ws.send(JSON.stringify(["EVENT", signedEvent]));
    log(`Sent message to relay: ${ws.url}`);
  } catch (error) {
    log(`Error signing profile: ${error.message}`);
    alert(`Error signing profile: ${error.message}`);
  }
}

// --- Event Listeners ---
document.addEventListener('DOMContentLoaded', () => {
    document.getElementById('connectButton').addEventListener('click', connectToNostr);
    document.getElementById('fetchEventButton').addEventListener('click', fetchEvent);
    document.getElementById('fetchProfileButton').addEventListener('click', fetchProfile);
    document.getElementById('editProfileButton').addEventListener('click', editProfile);

    log("App started");
});
