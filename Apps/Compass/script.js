let pubkey; // not used in the application
let sourceRelayUrl = null;
let ws;
let profile = {};
let relays = [];
let p2p = [];
let twelveP = [];
let p21 = [];
let allFollows = [];

// --- Utility Functions ---
function log(message) {
  const debugDiv = document.getElementById("debug");
  debugDiv.innerHTML += message + "<br>";
  console.log(message);
}

// --- Gestion d'Erreur Centralisée ---
function handleError(message, error = null) {
  console.error(message, error);
  log(`<strong>Error:</strong> ${message}`); // Affichage plus visible
}

// --- Profile Functions ---
async function fetchProfile() {
  const profilePubKey = document.getElementById("profilePubKey").value;
  sourceRelayUrl = document.getElementById("relayUrl").value;

  if (!profilePubKey || !sourceRelayUrl) {
    alert("Please enter both Pubkey and Relay URL");
    return;
  }

  log(`Fetching profile ${profilePubKey} from ${sourceRelayUrl}`);

  try {
    // Connect to the source relay
    ws = new WebSocket(sourceRelayUrl);
    await connectToRelay(ws);

    ws.addEventListener("message", async (event) => {
      const data = JSON.parse(event.data);

      if (data[0] === "EVENT") {
        const eventData = data[2];

        // Récupération du profil (kind 0)
        if (eventData.kind === 0 && eventData.pubkey === profilePubKey) {
          profile = JSON.parse(eventData.content);
          log(`Profile fetched: ${JSON.stringify(profile)}`);

          // Afficher le profil
          document.getElementById("profileName").textContent =
            profile.name || "Unknown";
          document.getElementById("profileAbout").textContent = profile.about || "";
          document.getElementById("profileNip05").textContent = `NIP-05: ${profile.nip05 || "N/A"
            }`;
          document.getElementById("profileLud16").textContent = `lud16: ${profile.lud16 || "N/A"
            }`;
          document.getElementById("profileAvatar").src =
            profile.picture || "default_avatar.png";
          document.getElementById("profileBanner").src = profile.banner || "";
        } else if (eventData.kind === 10002) {
          // Récupération des relays préférés (kind 10002)
          console.log(`RELAYS fetched: ${eventData.content}`);
          relays = eventData.tags.filter((item) => item[0] === "r");
          console.log(`RELAYS fetch successfully`);
          displayRelays(relays);
        } else if (eventData.kind === 3 && eventData.pubkey === profilePubKey) {
          // Analyse des relations
          allFollows = eventData.tags.filter((tag) => tag[0] === "p").map((tag) => tag[1]);
          await analyzeRelations(allFollows, profilePubKey);

          log(`allFollows: ${JSON.stringify(allFollows)}`);
        }
      } else if (data[0] === "EOSE") {
        log("EOSE received");

        // Nettoyer le listener après la réception des messages
        ws.removeEventListener("message", ws.onmessage);
        // Après avoir reçu l'EOSE, on demande aussi les relay de cette personne

        // Nettoyer le listener après la réception des messages

        ws.removeEventListener("message", ws.onmessage);
        // Après avoir reçu l'EOSE, on demande aussi les contacts et les relay de cette personne
        fetchRelations(ws, profilePubKey);
        // On fetch les relations et les relays ici pour les afficher dans le DOM.
        displayRelations("p2pList", p2p);
        displayRelations("twelvePList", twelveP);
        displayRelations("p21List", p21);
      } else {
        log(`Received: ${JSON.stringify(data)}`);
      }
    });
  } catch (error) {
    handleError("Failed to fetch profile.", error);
  }
}

// -- Function pour afficher les relais
function displayRelays(relays) {
  const relaysList = document.getElementById("relaysList");
  relaysList.innerHTML = "";
  if (!Array.isArray(relays) || relays.length === 0) {
    relaysList.innerHTML = "<li>No relays found.</li>";
    return;
  }
  relays.forEach((relay) => {
    const listItem = document.createElement("li");
    listItem.textContent = relay;
    relaysList.appendChild(listItem);
  });
}

// -- Await pour la récupération des relations
async function fetchRelations(ws, profilePubKey) {
  // Demande d'informations au serveur pour qu'il affiche les contact list et relias list
  ws.send(
    JSON.stringify([
      "REQ",
      "relays_req",
      {
        kinds: [10002],
        authors: [profilePubKey],
      },
    ])
  );
  ws.send(
    JSON.stringify([
      "REQ",
      "contacts_req",
      {
        kinds: [3],
        authors: [profilePubKey],
      },
    ])
  );
}

// -- Analyser les relations selon : P2P, 12P, et P21
async function analyzeRelations(allFollows, profilePubKey) {
  p2p = [];
  twelveP = [];
  p21 = [];
  // P2P: Suivi mutuel (A suit B et B suit A)
  p2p = allFollows.filter((follows) => allFollows.includes(follows));
  displayRelations("p2pList", p2p);

  // 12P: A -> B (les personnes suivies par A)
  twelveP = allFollows;
  displayRelations("twelvePList", twelveP);

  // P21: A <- B (les personnes qui suivent A)
  p21 = [];
  displayRelations("p21List", p21);
}

function displayRelations(elementId, relations) {
  const listElement = document.getElementById(elementId);
  listElement.innerHTML = "";

  if (!relations || relations.length === 0) {
    listElement.innerHTML = "<li>No relations found.</li>";
    return;
  }

  relations.forEach((relation) => {
    const listItem = document.createElement("li");
    listItem.textContent = relation;
    listElement.appendChild(listItem);
  });
}

async function connectToRelay(ws) {
  return new Promise((resolve, reject) => {
    ws.onopen = () => {
      log(`Connected to relay: ${ws.url}`);
      resolve();
    };

    ws.onerror = (error) => {
      handleError(`WebSocket error on ${ws.url}:`, error);
      reject(error);
    };

    ws.onclose = () => {
      log(`Disconnected from relay: ${ws.url}`);
    };
  });
}
// --- Event Listeners ---
document.addEventListener("DOMContentLoaded", () => {
  document
    .getElementById("fetchProfileButton")
    .addEventListener("click", fetchProfile);
});