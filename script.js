const connectButton = document.getElementById('connectButton');
const connectionStatus = document.getElementById('connectionStatus');
const feed = document.getElementById('feed');
const relayUrlInput = document.getElementById('relayUrl');
const profileSection = document.getElementById('profileSection');
const profilePicture = document.getElementById('profilePicture');
const profileName = document.getElementById('profileName');
const profileAbout = document.getElementById('profileAbout');
const categorySelectDiv = document.getElementById('categorySelection');

let nostr;
let userPubKey;
let relay;
let follows = new Set();
let userProfile = {};
let trustScores = new Map();
const profileReqId = "profile_req";
const followsReqId = "follows_req";
const feedReqId = "feed_req";
const trustReqId = "trust_req";
const limit = 20; // max number of posts loaded at once

let lastEventTime = null;
let loading = false;
let categories = new Set();
let selectedCategory = 'all';
let categorySelect;
let customCategoryInput;
let cachedRelays = []; // Add cache for relays
let categorySelectorInitialized = false; // Add a flag

const moodLevels = {
    '🤬': -100,
    '😠': -50,
    '😐': -10,
    '👍': 25,
    '😊': 50,
    '❤️': 100
};

// -- helper functions
function hexToNpub(hexPubKey) {
    // 1. Convert hex to bytes
    const bytes = [];
    for (let c = 0; c < hexPubKey.length; c += 2) {
        bytes.push(parseInt(hexPubKey.substring(c, c + 2), 16));
    }
    // 2. Encode bytes to base32
    const base32Chars = "abcdefghijklmnopqrstuvwxyz234567";
    let base32String = "";
    let buffer = 0;
    let bits = 0;

    for (let i = 0; i < bytes.length; i++) {
        buffer = (buffer << 8) | bytes[i];
        bits += 8;
        while (bits >= 5) {
            base32String += base32Chars[(buffer >>> (bits - 5)) & 31];
            bits -= 5;
        }
    }

    if (bits > 0) {
        base32String += base32Chars[(buffer << (5 - bits)) & 31];
    }

    // 3. Create the Bech32 string
    const hrp = "npub";
    const checksum = bech32Checksum(hrp, base32String);
    const bech32String = hrp + "1" + base32String + checksum;
    return bech32String;
}

function hexToNprofile1(hexPubKey, relays = []) {
    // 1. Convert hex pubkey to bytes
    const bytes = [];
    for (let c = 0; c < hexPubKey.length; c += 2) {
        bytes.push(parseInt(hexPubKey.substring(c, c + 2), 16));
    }
    // 2. Encode bytes to base32
    const base32Chars = "abcdefghijklmnopqrstuvwxyz234567";
    let base32String = "";
    let buffer = 0;
    let bits = 0;

    for (let i = 0; i < bytes.length; i++) {
        buffer = (buffer << 8) | bytes[i];
        bits += 8;
        while (bits >= 5) {
            base32String += base32Chars[(buffer >>> (bits - 5)) & 31];
            bits -= 5;
        }
    }

    if (bits > 0) {
        base32String += base32Chars[(buffer << (5 - bits)) & 31];
    }
    // 2.5 Add relay hints bytes (length of each URL in a byte and URL)
    for (const relay of relays) {
        const relayBytes = [].concat(...relay.split('').map((c) => c.charCodeAt(0) >>> 0));
        base32String += base32Chars[relayBytes.length];
        for (let j = 0; j < relayBytes.length; j++) {
            buffer = (buffer << 8) | relayBytes[j];
            bits += 8;
            while (bits >= 5) {
                base32String += base32Chars[(buffer >>> (bits - 5)) & 31];
                bits -= 5;
            }
        }
    }

    if (bits > 0) {
        base32String += base32Chars[(buffer << (5 - bits)) & 31];
    }
    // 3. Create the Bech32 string
    const hrp = "nprofile";
    const checksum = bech32Checksum(hrp, base32String);
    const bech32String = hrp + "1" + base32String + checksum;
    return bech32String;
}

function bech32Checksum(hrp, base32) {
    const values = [].concat(...hrp.split('').map((c) => c.charCodeAt(0) >>> 0), 0);
    const base32Bytes = base32.split('').map((c) => 'abcdefghijklmnopqrstuvwxyz234567'.indexOf(c));
    const combined = values.concat(base32Bytes)

    let polly = 1;

    for (let i = 0; i < combined.length; i++) {
        const byte = combined[i];
        polly = (polly ^ byte) >>> 0;
        for (let j = 0; j < 5; j++) {
            polly = (polly >>> 1) ^ (((polly & 1) === 0) ? 0 : 0x3cbc5)
        }
    }
    polly = (polly ^ 1) >>> 0;
    const checksumBytes = []
    for (let j = 0; j < 6; j++) {
        checksumBytes.push((polly >>> 0) & 31)
        polly = (polly >>> 5) >>> 0
    }
    return checksumBytes.reverse().map((b) => 'abcdefghijklmnopqrstuvwxyz234567'[b]).join('')
}

// --- UI helper functions
// Function to add new post
function addPostToFeed(event) {
    const post = document.createElement('div');
    post.classList.add('post');
    post.setAttribute('data-pubkey', event.pubkey);
    post.setAttribute('data-eventid', event.id);
    post.innerHTML = `<p>${event.content}</p><div class="trust-buttons"></div> <button class="show-trust-button">Show Ratings</button> <div class="trust-events" style="display: none;"></div>`;
    feed.appendChild(post);

    const trustButtonsDiv = post.querySelector('.trust-buttons');
    for (const mood in moodLevels) {
        const btn = document.createElement('button');
        btn.textContent = mood;
        btn.addEventListener('click', () => ratePost(post, mood));
        trustButtonsDiv.appendChild(btn);
    }

    const showTrustButton = post.querySelector('.show-trust-button');
    showTrustButton.addEventListener('click', () => toggleTrustEvents(post));

    updateTrustLevelDisplay(post, event.pubkey);
    // updateCategories
    updateCategories(post, event)
}

function addCategorySelectorToUI() {
    if (categorySelectorInitialized) {
        return; // Do not re-initialize if already done
    }

    categorySelect = document.createElement('select');
    categorySelect.id = 'category';

    const allOption = document.createElement('option');
    allOption.value = 'all';
    allOption.textContent = 'All';
    categorySelect.appendChild(allOption);


    customCategoryInput = document.createElement('input');
    customCategoryInput.type = 'text';
    customCategoryInput.id = 'customCategory';
    customCategoryInput.placeholder = 'Custom category';
    customCategoryInput.style.display = 'none';

    const label = document.createElement('label');
    label.htmlFor = 'category';
    label.textContent = 'Filter by Category:';

    categorySelectDiv.appendChild(label);
    categorySelectDiv.appendChild(categorySelect);
    categorySelectDiv.appendChild(customCategoryInput);

    categorySelect.addEventListener('change', function () {
        if (this.value === 'custom') {
            customCategoryInput.style.display = 'block';
            selectedCategory = customCategoryInput.value;
        } else {
            customCategoryInput.style.display = 'none';
            selectedCategory = this.value;
        }
        filterFeed();

    });
    customCategoryInput.addEventListener('change', function () {
        if (this.value) {
            selectedCategory = this.value;
            filterFeed();
        } else {
            selectedCategory = categorySelect.value;
            filterFeed();
        }
    });

    categorySelectorInitialized = true; // set the flag
}



// Function to add followed key to the UI
function addFollowedKeyToUI(pubkey) {
    const followedKeysList = document.getElementById('followedKeysList');
    console.log('addFollowedKeyToUI called for pubkey:', pubkey);

    // Check if the key already exists in the list
    if (followedKeysList.querySelector(`[data-pubkey="${pubkey}"]`)) {
        console.log('Pubkey already exists, skipping:', pubkey);
        return; // Do not add if it already exists
    }

    const listItem = document.createElement('li');
    listItem.setAttribute('data-pubkey', pubkey);
    const link = document.createElement('a');

    // Convert hex pubkey to nprofile1 format using cached relays
    const nprofile1 = hexToNprofile1(pubkey, cachedRelays);
    console.log('nprofile1 generated:', nprofile1);
    link.href = `https://nostter.app/${nprofile1}`;
    link.textContent = nprofile1;
    link.target = '_blank';
    listItem.appendChild(link);
    followedKeysList.appendChild(listItem);
    document.getElementById('followedKeysSection').style.display = 'block';
    console.log('Pubkey added to UI:', pubkey);
}


// Function to toggle the display of trust events
function toggleTrustEvents(postElement) {
    const trustEventsDiv = postElement.querySelector('.trust-events');
    const eventId = postElement.getAttribute('data-eventid');

    if (trustEventsDiv.style.display === 'none') {
        trustEventsDiv.style.display = 'block';
        fetchAndDisplayTrustEvents(postElement, eventId);
    } else {
        trustEventsDiv.style.display = 'none';
        trustEventsDiv.innerHTML = '';
    }
}

function clearFeed() {
    while (feed.firstChild) {
        feed.removeChild(feed.firstChild);
    }
}

function filterFeed() {
    clearFeed(); // Clear existing posts
    lastEventTime = null;
    fetchEvents()
}

function updateCategories(post, event) {
    if (event.tags) {
        event.tags.forEach(tag => {
            if (tag[0] === 'category') {
                categories.add(tag[1]);
            }
        })
    }

    // update categories UI
     updateCategoryOptions();
}

function updateCategoryOptions() {
    if (!categorySelect) return;

    categorySelect.innerHTML = '';

    const allOption = document.createElement('option');
    allOption.value = 'all';
    allOption.textContent = 'All';
    categorySelect.appendChild(allOption);

    categories.forEach(category => {
        const option = document.createElement('option');
        option.value = category;
        option.textContent = category;
        categorySelect.appendChild(option);
    });

    const customOption = document.createElement('option');
    customOption.value = 'custom';
    customOption.textContent = 'Custom';
    categorySelect.appendChild(customOption);
}

// --- Nostr functions
// Function to send a trust rating event
async function ratePost(postElement, mood) {
    if (!nostr) {
        alert('Vous devez d\'abord vous connecter avec Nostr Connect.');
        return;
    }

    const pubkey = postElement.getAttribute('data-pubkey');
    const eventId = postElement.getAttribute('data-eventid');
    const rating = moodLevels[mood];
    const relayUrl = relayUrlInput.value;

    let category = selectedCategory;
    if (selectedCategory == 'all') {
        category = 'general'
    }

    const trustEvent = {
        kind: 33,
        content: '',
        tags: [
            ['p', pubkey],
            ['rating', rating.toString()],
            ['e', eventId],
            ['category', category]
        ],
        created_at: Math.floor(Date.now() / 1000)
    };

    // Sign the event
    let signedEvent;
    try {
        signedEvent = await nostr.signEvent(trustEvent);
    } catch (error) {
        console.error("Error signing the event:", error);
        alert("Erreur lors de la signature de l'événement. Vérifiez l'extension Nostr Connect.")
    }

    try {
        if (signedEvent) {
            relay.send(JSON.stringify(["EVENT", signedEvent]));
            console.log('kind 33 Event envoyé: ', signedEvent);
        }
        updateTrustLevelDisplay(postElement, pubkey, true);

    } catch (error) {
        console.error("Error sending event:", error);
        alert("Erreur lors de l'envoi de l'event.")
    }
}


// Function to connect with Nostr Connect
connectButton.addEventListener('click', async () => {
    try {
        if (!nostr) {
            nostr = window.nostr;
        }
        if (nostr) {
            userPubKey = await nostr.getPublicKey();
            connectionStatus.textContent = 'Connecté à Nostr';
            // Try to get relays and set the input value
            try {
                const relays = await nostr.getRelays();

                if (relays) {
                    cachedRelays = Array.from(Object.keys(relays)); // Extract keys
                } else {
                    cachedRelays = [];
                }

            } catch (error) {
                console.warn('Error fetching relays:', error)
                alert('Error fetching relays from nostr extension, please check the console.')
                return;
            }


            console.log('Relays from nostr:', cachedRelays);

            let relayUrl = relayUrlInput.value;
            if (!relayUrl && cachedRelays && cachedRelays.length > 0) {
                relayUrl = cachedRelays[0];
                relayUrlInput.value = relayUrl;
                console.warn('No Relay found in input, using nostr relay :', relayUrl);
            } else if (!relayUrl) {
                console.warn('No Relay found in input or nostr plugin, please add a relay');
                alert('No Relay found in input or nostr plugin, please add a relay')
                return;
            }

            console.log('Nostr extension found:', nostr);

            relay = new WebSocket(relayUrl);

            relay.onopen = async () => {
                console.log("WebSocket connection opened.");
                 try {
                        await fetchUserProfile();
                        await fetchFollows();
                        addCategorySelectorToUI();
                         updateCategoryOptions();
                         fetchEvents();
                        // Add scroll listener for pagination
                        window.addEventListener('scroll', handleScroll);
                    } catch (error) {
                        console.error("Erreur lors du chargement des données utilisateur :", error)
                }
            };

            relay.onclose = () => {
                console.log("WebSocket connection closed.");
            };

            relay.onerror = (error) => {
                console.error("WebSocket error:", error);
            };

        } else {
            alert('Extension Nostr Connect non trouvée. Veuillez l\'installer.');
        }
    } catch (error) {
        console.error("Error connecting to Nostr:", error);
        alert('Erreur de connexion avec Nostr. Veuillez vérifier votre extension.');
    }
});

// Function to fetch user's profile (Kind 0)
async function fetchUserProfile() {
    return new Promise((resolve, reject) => {
        const filter = {
            kinds: [0],
            authors: [userPubKey]
        };
        relay.send(JSON.stringify(["REQ", profileReqId, filter]));
        console.log("REQ profile sent:", JSON.stringify(["REQ", profileReqId, filter]));

        relay.onmessage = (event) => {
            console.log("relay.onmessage received:", event) // Log the raw message
            const data = JSON.parse(event.data);

            if (data[0] === "EVENT") {
                const event = data[2];
                console.log("EVENT received for profile:", event);
                try {
                    userProfile = JSON.parse(event.content);
                    console.log('User Profile parsed:', userProfile);

                    // show profile Section
                    profileSection.style.display = 'block'

                    if (userProfile.name) {
                        profileName.textContent = userProfile.name;
                    }
                    if (userProfile.picture) {
                        profilePicture.src = userProfile.picture;
                    }
                    if (userProfile.about) {
                        profileAbout.textContent = userProfile.about;
                    }
                    resolve();
                } catch (error) {
                    console.error("Error parsing user profile:", error);
                    reject(error)
                }

            } else if (data[0] === "EOSE") {
                console.log('EOSE received for profile');
                resolve(); // Resolve the promise when EOSE is received.
            } else if (data[0] === 'NOTICE') {
                console.log('NOTICE received for profile:', data)
                reject(data); // Reject on 'NOTICE'
            }
        }
        relay.onerror = (error) => {
            console.error("WebSocket error in fetchUserProfile:", error);
            reject(error); // Reject the promise if WebSocket has an error.
        };
    })
}

/// Function to fetch the public key the user is following
async function fetchFollows() {
    return new Promise((resolve, reject) => {
        const followedKeysList = document.getElementById('followedKeysList');
        followedKeysList.innerHTML = ''; // Clear existing list

        const filter = {
            kinds: [3],
            authors: [userPubKey]
        };
        relay.send(JSON.stringify(["REQ", followsReqId, filter]));
        console.log('REQ follow sent', filter);
        relay.onmessage = (event) => {
            const data = JSON.parse(event.data);
            if (data[0] === "EVENT") {
                const event = data[2];
                if (event.kind === 3 && event.pubkey === userPubKey) {
                    event.tags.forEach(tag => {
                        if (tag[0] === 'p') {
                            follows.add(tag[1]);
                            addFollowedKeyToUI(tag[1]);
                        }
                    });
                }
            }
            if (data[0] === "EOSE") {
                console.log('Follows have been fetched');
                resolve();
            }
        };
    });
}

// Function to fetch the user's note
function fetchEvents() {
    if (loading) return;
    loading = true;
    let filter = {
        kinds: [1],
        authors: [...follows, userPubKey],
        limit: limit
    };
    // Remove the until filter so we don't limit by time
    /*if (lastEventTime) {
        filter.until = lastEventTime;
    }*/

    relay.send(JSON.stringify(["REQ", feedReqId, filter]));
    console.log('REQ fetchEvents sent', filter);

    relay.onmessage = (event) => {
        const data = JSON.parse(event.data);
        if (data[0] === "EVENT") {
            const eventData = data[2];
            addPostToFeed(eventData);
           lastEventTime = eventData.created_at;
        }
        if (data[0] === 'EOSE') {
            console.log('EOSE for events received');
            loading = false;
             updateCategories();
        }
    };
};

// Function to fetch and display trust events
async function fetchAndDisplayTrustEvents(postElement, eventId) {
    const trustEventsDiv = postElement.querySelector('.trust-events');
        let filter = {
            kinds: [33],
            "#e": [eventId]
        };
          if (selectedCategory !== 'all' && selectedCategory !== 'general'){
              filter["#category"] = [selectedCategory]
        }
    relay.send(JSON.stringify(["REQ", trustReqId, filter]));
    trustEventsDiv.innerHTML = '';
    let ratings = [];
    relay.onmessage = (event) => {
        const data = JSON.parse(event.data);

        if (data[0] === "EVENT") {
            const event = data[2];
            if (event.tags && event.tags.length > 0) {
                let rating = null;
                let targetPubKey = null;
                let category = 'N/A'
                event.tags.forEach(tag => {
                    if (tag[0] === 'rating') {
                        rating = parseFloat(tag[1])
                    }
                    if (tag[0] === 'p') {
                        targetPubKey = tag[1]
                    }
                    if (tag[0] === 'category') {
                        category = tag[1]
                    }
                });
                const eventDiv = document.createElement('div');
                eventDiv.textContent = `User: ${targetPubKey}, Rating: ${rating}, Category: ${category}`;
                trustEventsDiv.appendChild(eventDiv);
                if (rating) {
                    ratings.push(rating);
                }
            }
        }
        if (data[0] === "EOSE") {
            let averageRating = null;
            if (ratings.length > 0) {
                const sum = ratings.reduce((acc, rating) => acc + rating, 0);
                averageRating = sum / ratings.length;
            }
            const averageDiv = document.createElement('div');
            averageDiv.textContent = `Average Rating: ${averageRating !== null ? averageRating.toFixed(2) : "N/A"}`
            trustEventsDiv.appendChild(averageDiv)

            console.log('Trust events have been fetched')
        }
    }
}

// Function to calculate trust scores
async function calculateTrustScores(targetPubKey, category) {
    const allRatings = new Map();
    const friendRatings = new Map();
     const categoryRatings = new Map();
    const friendCategoryRatings = new Map();


    return new Promise(async (resolve) => {
        const filter = {
            kinds: [33],
            "#p": [targetPubKey],
        };
         if (category !== 'all' && category !== 'general'){
            filter["#category"] = [category]
        }
        relay.send(JSON.stringify(["REQ", trustReqId, filter]));

        relay.onmessage = (event) => {
            const data = JSON.parse(event.data);
            if (data[0] === "EVENT") {
                const event = data[2];
                let rating = null;
                let eventCategory = 'general';
                event.tags.forEach(tag => {
                    if (tag[0] === 'rating') {
                        rating = parseFloat(tag[1])
                    }
                    if (tag[0] === 'category') {
                        eventCategory = tag[1]
                    }
                });
                if (rating !== null) {
                    allRatings.set(event.pubkey, rating);
                   if (follows.has(event.pubkey)) {
                        friendRatings.set(event.pubkey, rating);
                           if (category === eventCategory) {
                                friendCategoryRatings.set(event.pubkey,rating);
                         }
                     }
                      if (category === eventCategory) {
                           categoryRatings.set(event.pubkey, rating);
                       }
                }
            }
            if (data[0] === "EOSE") {
                const allScore = calculateAverage(Array.from(allRatings.values()));
                 const friendsScore = calculateAverage(Array.from(friendRatings.values()));
                  const categoryScore = calculateAverage(Array.from(categoryRatings.values()));
                const friendCategoryScore = calculateAverage(Array.from(friendCategoryRatings.values()))
                resolve({
                     allScore: allScore,
                    friendsScore: friendsScore,
                      categoryScore: categoryScore,
                       friendCategoryScore : friendCategoryScore
                });
            }
        };
    });
}

// Function to fetch kind 33 events & display Trust event list
async function fetchAndDisplayTrustEvents(postElement, eventId) {
    const trustEventsDiv = postElement.querySelector('.trust-events');
        let filter = {
            kinds: [33],
            "#e": [eventId]
        };
          if (selectedCategory !== 'all' && selectedCategory !== 'general'){
              filter["#category"] = [selectedCategory]
        }
    relay.send(JSON.stringify(["REQ", trustReqId, filter]));
    trustEventsDiv.innerHTML = '';
    let ratings = [];
    relay.onmessage = (event) => {
        const data = JSON.parse(event.data);

        if (data[0] === "EVENT") {
            const event = data[2];
            if (event.tags && event.tags.length > 0) {
                let rating = null;
                let targetPubKey = null;
                let category = 'N/A'
                event.tags.forEach(tag => {
                    if (tag[0] === 'rating') {
                        rating = parseFloat(tag[1])
                    }
                    if (tag[0] === 'p') {
                        targetPubKey = tag[1]
                    }
                    if (tag[0] === 'category') {
                        category = tag[1]
                    }
                });
                const eventDiv = document.createElement('div');
                eventDiv.textContent = `User: ${targetPubKey}, Rating: ${rating}, Category: ${category}`;
                trustEventsDiv.appendChild(eventDiv);
                if (rating) {
                    ratings.push(rating);
                }
            }
        }
        if (data[0] === "EOSE") {
            let averageRating = null;
            if (ratings.length > 0) {
                const sum = ratings.reduce((acc, rating) => acc + rating, 0);
                averageRating = sum / ratings.length;
            }
            const averageDiv = document.createElement('div');
            averageDiv.textContent = `Average Rating: ${averageRating !== null ? averageRating.toFixed(2) : "N/A"}`
            trustEventsDiv.appendChild(averageDiv)

            console.log('Trust events have been fetched')
        }
    }
}


function calculateAverage(ratings) {
    if (ratings.length === 0) {
        return null;
    }
    const sum = ratings.reduce((acc, rating) => acc + rating, 0);
    return sum / ratings.length;
}

// Update the trust level on the UI
async function updateTrustLevelDisplay(postElement, targetPubKey, voted = false) {
    const trustLevelDisplay = postElement.querySelector('.trust-level') || document.createElement('div');
    trustLevelDisplay.classList.add('trust-level');
    const trustButtonsDiv = postElement.querySelector('.trust-buttons');


    try {
          const {allScore, friendsScore, categoryScore, friendCategoryScore} = await calculateTrustScores(targetPubKey, selectedCategory === 'all' ? 'general' : selectedCategory);

           let  trustText = `All: ${allScore !== null ? allScore.toFixed(2) : 'N/A'}`;
            if(friendsScore !== null) trustText +=  `, Friends: ${friendsScore !== null ? friendsScore.toFixed(2) : 'N/A'}`;
            if(categoryScore !== null && selectedCategory !== 'all') trustText += `, Category: ${categoryScore !== null ? categoryScore.toFixed(2) : 'N/A'}`
             if(friendCategoryScore !== null && selectedCategory !== 'all') trustText += `, Category Friends: ${friendCategoryScore !== null ? friendCategoryScore.toFixed(2) : 'N/A'}`

            trustLevelDisplay.textContent = trustText;
            postElement.appendChild(trustLevelDisplay);

        if(voted){
               trustButtonsDiv.style.display = 'none';
             } else {
                trustButtonsDiv.style.display = 'flex';
            }
    } catch (error) {
        console.error("Error updating trust level:", error);
         trustLevelDisplay.textContent = `Error fetching score`;
            postElement.appendChild(trustLevelDisplay);
    }
}


// Function to handle infinite scrolling
function handleScroll() {
    if (loading) return;
    const scrollY = window.scrollY;
    const windowHeight = window.innerHeight;
    const documentHeight = document.documentElement.scrollHeight;
    if (scrollY + windowHeight >= documentHeight - 100) {
        fetchEvents()
    }
}


// Function to refresh the feed
async function refreshFeed() {
    clearFeed(); // Clear existing posts
    lastEventTime = null;
    categories.clear(); // Clear existing categories
    follows.clear();
    await fetchFollows();
    fetchEvents();
}

// Add a refresh button next to "Connecter avec Nostr"
const refreshButton = document.createElement('button');
refreshButton.textContent = 'Rafraîchir';
refreshButton.id = 'refreshButton';
refreshButton.addEventListener('click', refreshFeed);
connectButton.parentNode.insertBefore(refreshButton, connectButton.nextSibling);
