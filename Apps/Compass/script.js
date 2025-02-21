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

// --- Decode npub1 to Hex ---
function decodeNpub(npub) {
  try {
    const { type, data } = window.NostrTools.nip19.decode(npub);
    if (type === "npub") {
      return data;
    } else {
      throw new Error("Invalid npub key");
    }
  } catch (error) {
    handleError("Failed to decode npub key:", error);
    return null;
  }
}

// --- Profile Functions ---
async function fetchProfile(profileKey) {
  // Check if profileKey is a valid string
  if (typeof profileKey !== "string" || !profileKey) {
    handleError("Invalid profile key.");
    return;
  }

  // Check if the key is a valid npub key or a raw public key
  const isNpub = profileKey.startsWith("npub1");
  const profilePubKey = isNpub ? decodeNpub(profileKey) : profileKey;

  if (!profilePubKey) {
    handleError("Invalid public key format.");
    return;
  }

  // Continue with the WebSocket connection and fetching logic
  sourceRelayUrl = document.getElementById("relayUrl").value;
  log(`fetchProfile - Connecting to relay: ${sourceRelayUrl}`);

  try {
    const ws = new WebSocket(sourceRelayUrl);
    ws.addEventListener("open", () => {
      log(`Connected to relay: ${ws.url}`);
      ws.send(
        JSON.stringify([
          "REQ",
          "profile_req",
          {
            kinds: [0, 3, 10002], // Fetch profile metadata (kind 0), contacts (kind 3), and relays (kind 10002)
            authors: [profilePubKey],
          },
        ])
      );
    });

    ws.addEventListener("message", async (event) => {
      const data = JSON.parse(event.data);
      log(`Received data: ${JSON.stringify(data)}`);

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
          document.getElementById("profileWebsite").textContent = `Website: ${profile.website || "N/A"
            }`;
          document.getElementById("profileAvatar").src =
            profile.picture || "default_avatar.png";
          document.getElementById("profileBanner").src = profile.banner || "";
        } else if (eventData.kind === 10002) {
          // Récupération des relays préférés (kind 10002)
          relays = eventData.tags.filter((item) => item[0] === "r");
          log(`RELAYS fetched: ${JSON.stringify(relays)}`);
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

        // Afficher les relations
        displayRelations("p2pList", p2p);
        displayRelations("twelvePList", twelveP);
        displayRelations("p21List", p21);
      }
    });

    ws.addEventListener("error", (error) => {
      handleError("WebSocket error:", error);
    });

    ws.addEventListener("close", () => {
      log("WebSocket connection closed.");
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
    const slide = document.createElement("div");
    slide.className = "swiper-slide";
    slide.innerHTML = `<div>${relay[1]}</div>`; // Relay URL is in the second position of the tag array
    relaysList.appendChild(slide);
  });

  // Initialize Swiper for the relays carousel
  new Swiper('.swiper-container', {
    slidesPerView: 3,
    spaceBetween: 10,
    navigation: {
      nextEl: '.swiper-button-next',
      prevEl: '.swiper-button-prev',
    },
    pagination: {
      el: '.swiper-pagination',
      clickable: true,
    },
  });
}

// --- Fetch Followers Function ---
async function fetchFollowers(profilePubKey) {
  const followers = [];
  const relayUrl = sourceRelayUrl; // Use the current relay URL
  log(`fetchFollowers - Connecting to relay: ${relayUrl}`);
  try {
    const ws = new WebSocket(relayUrl);

    return new Promise((resolve, reject) => {
      ws.addEventListener("open", () => {
        log(`Connected to relay: ${ws.url}`);
        // Send a REQ message to fetch followers
        ws.send(
          JSON.stringify([
            "REQ",
            "followers_req",
            {
              kinds: [3], // Fetch followers (kind 3)
              authors: [profilePubKey],
            },
          ])
        );
      });

      ws.addEventListener("message", (event) => {
        const data = JSON.parse(event.data);
        log(`Received data: ${JSON.stringify(data)}`);

        if (data[0] === "EVENT" && data[2].pubkey === profilePubKey) {
          const eventData = data[2];
          const follows = eventData.tags.filter((tag) => tag[0] === "p").map((tag) => tag[1]);
          followers.push(...follows);
        } else if (data[0] === "EOSE") {
          log("EOSE received");
          ws.close(); // Close the WebSocket connection after receiving all data
          resolve(followers); // Resolve the promise with the followers
        }
      });

      ws.addEventListener("error", (error) => {
        handleError("WebSocket error:", error);
        reject(error);
      });

      ws.addEventListener("close", () => {
        log("WebSocket connection closed.");
      });
    });
  } catch (error) {
    handleError("Failed to fetch followers.", error);
    return [];
  }
}

// -- Analyser les relations selon : P2P, 12P, et P21
async function analyzeRelations(allFollows, profilePubKey) {
  p2p = [];
  twelveP = [];
  p21 = [];

  // 12P: Users followed by the profile (no change needed)
  twelveP = allFollows;

  // P21: Users who follow the profile (no change needed)
  const followers = await fetchFollowers(profilePubKey); // Already fetched correctly
  p21 = followers;

  // P2P: Mutual Follows (Intersection of allFollows and followers) - CORRECT LOGIC
  const followersSet = new Set(followers); // For efficient lookups
  for (const follow of allFollows) {
    if (followersSet.has(follow)) { // Efficiently check if 'follow' is in 'followers'
      p2p.push(follow);
    }
  }

  console.log("P2P Relations:", p2p);
  console.log("12P Relations:", twelveP);
  console.log("P21 Relations:", p21);

  displayRelations("p2pList", p2p);
  displayRelations("twelvePList", twelveP);
  displayRelations("p21List", p21);
}


// Function to fetch profile information (kind 0)
async function displayRelations(elementId, relations) {
  const swiperWrapper = document.getElementById(elementId);
  if (!swiperWrapper) {
    console.error(`Element with ID "${elementId}" not found.`);
    return;
  }

  swiperWrapper.innerHTML = ""; // Clear existing content
  log(`displayRelations - Called for elementId: ${elementId}, relations count: ${relations ? relations.length : 0}`);

  if (!relations || relations.length === 0) {
    swiperWrapper.innerHTML = "<div class='swiper-slide'>No relations found.</div>";
    return;
  }

  const slides = []; // Array to hold slide elements

  // Fetch profile information for each relation
  for (let i = 0; i < relations.length; i++) {
    const relation = relations[i];
    log(`displayRelations - Processing relation index: ${i}, pubkey: ${relation} for elementId: ${elementId}`);
    try {
      const profile = await fetchProfileInfo(relation);
      if (profile && Object.keys(profile).length > 0) {
        const slide = document.createElement("div");
        slide.className = "swiper-slide";
        slide.innerHTML = `
          <img src="${profile.picture || "default_avatar.png"}" alt="Avatar">
          <h4>${profile.name || "Unknown"}</h4>
          <p>Click to explore</p>
          <div class="friend-count">${relations.length} friends</div>
        `;

        // Add click event to explore the profile
        slide.addEventListener("click", () => {
          document.getElementById("profilePubKey").value = relation;
          fetchProfile(relation); // Fetch and display the selected profile
        });

        slides.push(slide);
        swiperWrapper.appendChild(slide);
      } else {
        log(`displayRelations - No profile data fetched for pubkey: ${relation}, index: ${i}, elementId: ${elementId}`);
      }
    } catch (error) {
      handleError(`displayRelations - Error fetching profile info for pubkey: ${relation}, index: ${i}, elementId: ${elementId}`, error); // Error log in displayRelations
    }
  }

  // Initialize Swiper AFTER the loop, if there are slides to initialize with
  if (slides.length > 0) {
    new Swiper(`#${elementId} .swiper-container`, {
      slidesPerView: 3,
      spaceBetween: 10,
      navigation: {
        nextEl: `#${elementId} .swiper-button-next`,
        prevEl: `#${elementId} .swiper-button-prev`,
      },
      pagination: {
        el: `#${elementId} .swiper-pagination`,
        clickable: true,
      },
    });
  } else {
    log(`displayRelations - No relations to initialize Swiper for elementId: ${elementId}`);
  }
}

// Function to fetch profile information (kind 0)
async function fetchProfileInfo(pubkey) {
  const relayUrl = sourceRelayUrl; // Use the current relay URL
  log(`fetchProfileInfo - Connecting to relay: ${relayUrl} for pubkey: ${pubkey}`);

  try {
    const ws = new WebSocket(relayUrl);
    let eventReceived = false; // Flag to track if an event is received

    return new Promise((resolve, reject) => {
      const timeoutId = setTimeout(() => { // Timeout for fetchProfileInfo
        ws.close();
        reject(new Error(`fetchProfileInfo - Timeout for pubkey: ${pubkey} after 5 seconds`)); // Reject on timeout
      }, 5000); // 5 seconds timeout

      ws.addEventListener("open", () => {
        log(`fetchProfileInfo - WebSocket opened for pubkey: ${pubkey}`);
        ws.send(
          JSON.stringify([
            "REQ",
            "profile_info_req",
            {
              kinds: [0], // Fetch profile metadata (kind 0)
              authors: [pubkey],
            },
          ])
        );
      });

      ws.addEventListener("message", (event) => {
        eventReceived = true; // Mark event as received
        const data = JSON.parse(event.data);
        log(`fetchProfileInfo - Message received for pubkey: ${pubkey}: ${JSON.stringify(data)}`); // Log message received
        if (data[0] === "EVENT" && data[2].kind === 0) {
          const profile = JSON.parse(data[2].content);
          log(`fetchProfileInfo - Profile data found for pubkey: ${pubkey}: ${JSON.stringify(profile)}`);
          clearTimeout(timeoutId); // Clear timeout on success
          resolve(profile);
          ws.close();
          log(`fetchProfileInfo - WebSocket closed for pubkey: ${pubkey} (success)`);
        }
      });

      ws.addEventListener("error", (error) => {
        clearTimeout(timeoutId); // Clear timeout on error
        handleError(`fetchProfileInfo - WebSocket error for pubkey: ${pubkey}`, error);
        reject(error);
      });

      ws.addEventListener("close", () => {
        clearTimeout(timeoutId); // Clear timeout on close
        if (!eventReceived) {
          log(`fetchProfileInfo - WebSocket closed prematurely for pubkey: ${pubkey} (no event received)`); // Log premature close
          reject(new Error(`fetchProfileInfo - WebSocket closed prematurely for pubkey: ${pubkey} (no event received)`));
        } else {
          log(`fetchProfileInfo - WebSocket closed for pubkey: ${pubkey} (no profile found after event or EOSE)`);
          resolve({}); // Return an empty object if no profile is found after event or EOSE
        }
      });
    });
  } catch (error) {
    handleError(`fetchProfileInfo - Failed to fetch profile info for pubkey: ${pubkey}`, error);
    return {};
  }
}

async function fetchFollowersWithRetry(profilePubKey, retries = 3) {
  for (let attempt = 0; attempt < retries; attempt++) {
    const followers = await fetchFollowers(profilePubKey);
    if (followers.length > 0) {
      return followers; // Successfully fetched followers
    }
    log(`Retrying to fetch followers... Attempt ${attempt + 1}`);
    await new Promise(resolve => setTimeout(resolve, 1000)); // Wait 1 second before retrying
  }
  return []; // Return empty if all retries fail
}

// --- Event Listeners ---
document.addEventListener("DOMContentLoaded", () => {
  document
    .getElementById("fetchProfileButton")
    .addEventListener("click", () => {
      const profileKey = document.getElementById("profilePubKey").value;
      fetchProfile(profileKey); // Pass the profileKey to fetchProfile
    });
});
