// script.js
document.addEventListener('DOMContentLoaded', () => {
    // --- STATE ---
    let userPubKey = null;
    let userProfile = {}; // Store Kind 0
    let userFollows = []; // Array of pubkeys user follows (from Kind 3)
    let relays = []; // Array of { url: string, read: boolean, write: boolean }
    let nostrSubscriptions = {}; // To manage active subscriptions by ID
    let currentMessages = []; // For N1/N2 wall
    let UPlanetData = null; // For map data
    let leafletMap = null;

    // Default relays if NIP-07 or Kind 10002 don't provide any
    const DEFAULT_RELAYS = [
        { url: 'wss://relay.damus.io', read: true, write: true },
        { url: 'wss://relay.snort.social', read: true, write: true },
        { url: 'wss://relay.copylaradio.com', read: true, write: true }
    ];

    // --- DOM ELEMENTS ---
    const connectButton = document.getElementById('connect-button');
    const connectionBadge = document.getElementById('connection-badge');
    const connectionText = document.getElementById('connection-text');
    const statusIndicator = document.getElementById('status-indicator');
    const darkModeToggle = document.getElementById('dark-mode-toggle');
    const menuToggleButton = document.getElementById('menu-toggle-button');
    const appSidebar = document.getElementById('app-sidebar');

    // Profile Sidebar
    const profileBannerImg = document.getElementById('profile-banner-img');
    const profileAvatarImg = document.getElementById('profile-avatar-img');
    const profileNameElem = document.getElementById('profile-name');
    const profileAboutElem = document.getElementById('profile-about');
    const statPostsElem = document.getElementById('stat-posts'); // Will update with message count later
    const editProfileButton = document.getElementById('edit-profile-button'); // in sidebar
    const viewProfileLink = document.querySelector('.view-profile-link');

    // Relays Sidebar
    const relaysListElem = document.getElementById('relays-list');

    // Main Content Navigation
    const contentMenuItems = document.querySelectorAll('.content-menu .menu-item');
    const contentSections = document.querySelectorAll('.content-section');

    // Detailed Profile Section
    const detailedProfileInfo = document.getElementById('detailed-profile-info');
    const profileNpubDisplay = document.getElementById('profile-npub-display');
    const profileNprofileDisplay = document.getElementById('profile-nprofile-display');
    const profileNip05Display = document.getElementById('profile-nip05-display');


    // N1/N2 Wall Section
    const nostrMessagesFeed = document.getElementById('nostr-messages-feed');
    const messageFeedContent = document.getElementById('message-feed-content');
    const nostrFeedLoading = document.getElementById('nostr-feed-loading');
    const loadMoreMessagesButton = document.getElementById('load-more-messages');
    const noMoreMessagesElem = document.getElementById('no-more-messages');
    const messageFeedErrorElem = document.getElementById('message-feed-error');


    // Profile Editor Section
    const profileEditorSection = document.getElementById('profile-editor');
    const profileForm = document.getElementById('profile-form');
    const nameInput = document.getElementById('name');
    const aboutInput = document.getElementById('about');
    const pictureInput = document.getElementById('picture');
    const bannerInput = document.getElementById('banner');
    const cancelProfileEditButton = document.getElementById('cancel-profile-edit');

    // New Message Section
    const newMessageForm = document.getElementById('new-message-form');
    const messageContentInput = document.getElementById('message-content');
    // const imageUploadInput = document.getElementById('image-upload'); // For later
    // const messagePreview = document.getElementById('message-preview'); // For later

    // UPlanet Section
    const uplanetMapDiv = document.getElementById('uplanet-map');
    // const uplanetPostsDiv = document.getElementById('uplanet-posts'); // For later

    // Relay Logs Section
    const relayLogsOutput = document.getElementById('relay-logs-output');

    // --- UTILS ---
    const logToRelayOutput = (message, type = 'INFO') => {
        const timestamp = new Date().toLocaleTimeString();
        relayLogsOutput.value += `[${timestamp}] [${type}] ${message}\n`;
        relayLogsOutput.scrollTop = relayLogsOutput.scrollHeight; // Auto-scroll
    };

    // NIP-19 (for npub, nprofile) - Basic implementations
    // For full NIP-19, a library like nostr-tools or nostr-sdk is recommended
    function hexToBech32(prefix, hexStr) {
        // This is a placeholder. Real bech32 encoding is complex.
        // You'd typically use a library for this.
        // Example: return someLibrary.nip19.npubEncode(hexStr);
        if (hexStr && hexStr.length === 64) {
           return `${prefix}1` + hexStr.substring(0, 8) + "..." + hexStr.substring(56);
        }
        return "Invalid hex for bech32";
    }


    // --- NOSTR CORE LOGIC ---
    async function connectNostr() {
        if (!window.nostr) {
            alert('Nostr extension (NIP-07) not found. Please install Alby, nos2x, or another compatible extension.');
            logToRelayOutput('NIP-07 extension not found.', 'ERROR');
            return;
        }
        try {
            logToRelayOutput('Attempting to connect via NIP-07...');
            userPubKey = await window.nostr.getPublicKey();
            if (userPubKey) {
                logToRelayOutput(`Connected with pubkey: ${userPubKey.substring(0, 10)}...`, 'SUCCESS');
                updateConnectionStatus(true);
                connectButton.textContent = 'Déconnecter'; // Or hide
                await loadUserNostrData();
            }
        } catch (err) {
            alert(`Connection failed: ${err.message || err}`);
            logToRelayOutput(`NIP-07 connection error: ${err.message || err}`, 'ERROR');
            updateConnectionStatus(false);
        }
    }

    function disconnectNostr() {
        userPubKey = null;
        userProfile = {};
        userFollows = [];
        // relays = []; // Maybe keep relays unless user explicitly clears them
        currentMessages = [];
        // Close all nostr subscriptions
        Object.values(nostrSubscriptions).forEach(sub => sub.unsub());
        nostrSubscriptions = {};

        updateConnectionStatus(false);
        connectButton.textContent = 'Connecter';
        clearUI();
        logToRelayOutput('Disconnected.', 'INFO');
    }

    function updateConnectionStatus(isConnected) {
        if (isConnected) {
            connectionBadge.classList.add('connected');
            statusIndicator.style.backgroundColor = 'green';
            connectionText.textContent = 'Connecté';
        } else {
            connectionBadge.classList.remove('connected');
            statusIndicator.style.backgroundColor = 'gray';
            connectionText.textContent = 'Déconnecté';
        }
    }

    async function loadUserNostrData() {
        if (!userPubKey) return;

        // 1. Get Relays
        await fetchUserRelays();

        // 2. Fetch Profile (Kind 0)
        await fetchUserProfile(userPubKey, true); // true to update main UI

        // 3. Fetch Follows (Kind 3)
        await fetchUserFollows();

        // 4. Load N1/N2 Wall (initial load)
        await loadNostrWallMessages(true);
    }

    async function fetchUserRelays() {
        logToRelayOutput('Fetching user relays...');
        try {
            if (window.nostr && typeof window.nostr.getRelays === 'function') {
                const nip07Relays = await window.nostr.getRelays(); // Returns {[url]: {read, write}}
                if (nip07Relays && Object.keys(nip07Relays).length > 0) {
                    relays = Object.entries(nip07Relays).map(([url, perms]) => ({ url, ...perms }));
                    logToRelayOutput(`Fetched ${relays.length} relays from NIP-07.`, 'INFO');
                    updateRelaysListUI();
                    return;
                }
            }
            // Fallback or if NIP-07 gives no relays: try Kind 10002
            // This requires a more complex setup with a connected relay pool.
            // For now, if NIP-07 fails, use defaults.
            logToRelayOutput('NIP-07 getRelays not available or returned empty. Using default relays.', 'WARN');
            relays = [...DEFAULT_RELAYS];

        } catch (err) {
            logToRelayOutput(`Error fetching relays: ${err.message || err}. Using defaults.`, 'ERROR');
            relays = [...DEFAULT_RELAYS];
        }
        updateRelaysListUI();
    }

    function getActiveReadRelays() {
        return relays.filter(r => r.read).map(r => r.url);
    }
    function getActiveWriteRelays() {
         return relays.filter(r => r.write).map(r => r.url);
    }


    async function fetchUserProfile(pubkey, isCurrentUser = false) {
        if (!pubkey) return null;
        logToRelayOutput(`Fetching profile for ${pubkey.substring(0, 8)}...`);

        const readRelays = getActiveReadRelays();
        if (readRelays.length === 0) {
            logToRelayOutput('No read relays configured to fetch profile.', 'ERROR');
            return null;
        }

        // Basic caching can be added here if fetching profiles for many users.
        // For current user, we always want fresh for now.

        let profileData = null;
        // Try fetching from multiple relays, take the first good one.
        for (const relayUrl of readRelays) {
            try {
                const relay = nostrTools.relayInit(relayUrl);
                await relay.connect();
                logToRelayOutput(`Connected to ${relayUrl} for profile fetch.`);

                const sub = relay.sub([{ kinds: [0], authors: [pubkey], limit: 1 }]);
                profileData = await new Promise((resolve, reject) => {
                    let eventData = null;
                    const timeout = setTimeout(() => {
                        sub.unsub();
                        relay.close();
                        reject(new Error(`Timeout fetching profile from ${relayUrl}`));
                    }, 5000);

                    sub.on('event', event => {
                        clearTimeout(timeout);
                        try {
                            eventData = JSON.parse(event.content);
                            eventData.pubkey = event.pubkey; // Store pubkey with profile
                            eventData.created_at = event.created_at; // Store for recency check
                            // logToRelayOutput(`Profile event from ${relayUrl}: ${JSON.stringify(eventData)}`);
                        } catch (e) {
                           logToRelayOutput(`Error parsing profile JSON from ${relayUrl}: ${e}`, 'ERROR');
                        }
                    });
                    sub.on('eose', () => {
                        clearTimeout(timeout);
                        sub.unsub();
                        relay.close();
                        resolve(eventData); // Resolve with data or null if no event
                    });
                     relay.on('error', (err) => { // Added by me
                        clearTimeout(timeout);
                        sub.unsub();
                        try { relay.close(); } catch(e){}
                        logToRelayOutput(`Relay error at ${relayUrl} while fetching profile: ${err}`, 'ERROR');
                        reject(err); // Reject promise to try next relay
                    });
                });
                relay.close(); // Ensure close

                if (profileData) {
                     // If we get data, potentially merge if other relays provide newer data
                    if (!userProfile.pubkey || (profileData.created_at && profileData.created_at > (userProfile.created_at || 0))) {
                         if (isCurrentUser) userProfile = profileData;
                    }
                    logToRelayOutput(`Successfully fetched profile from ${relayUrl}.`);
                    break; // Got profile, no need to check other relays for this basic fetch
                }
            } catch (err) {
                logToRelayOutput(`Failed to fetch profile from ${relayUrl}: ${err.message || err}`, 'WARN');
            }
        }

        if (isCurrentUser) {
            if (Object.keys(userProfile).length > 0) {
                 updateProfileUI(userProfile);
                 updateDetailedProfileUI(userProfile);
            } else {
                logToRelayOutput(`Could not fetch user profile for ${pubkey.substring(0,8)}.`, 'ERROR');
                // Still set some defaults if pubkey is available
                updateProfileUI({ name: pubkey.substring(0,10)+"...", pubkey: pubkey });
                updateDetailedProfileUI({ pubkey: pubkey });
            }
        }
        return userProfile; // Or the fetched profileData if not current user
    }


    async function fetchUserFollows() {
        if (!userPubKey) return;
        logToRelayOutput(`Fetching follows for ${userPubKey.substring(0, 8)}...`);
        const readRelays = getActiveReadRelays();
        if (readRelays.length === 0) {
            logToRelayOutput('No read relays configured to fetch follows.', 'ERROR');
            return;
        }

        let latestKind3Event = null;

        for (const relayUrl of readRelays) {
            try {
                const relay = nostrTools.relayInit(relayUrl);
                await relay.connect();
                const sub = relay.sub([{ kinds: [3], authors: [userPubKey], limit: 1 }]);
                const event = await new Promise((resolve, reject) => {
                    let k3 = null;
                    const timeout = setTimeout(() => {
                        sub.unsub();
                        relay.close();
                        reject(new Error(`Timeout fetching Kind 3 from ${relayUrl}`));
                    }, 5000);
                    sub.on('event', ev => {
                        clearTimeout(timeout);
                        k3 = ev;
                    });
                    sub.on('eose', () => {
                        clearTimeout(timeout);
                        sub.unsub();
                        relay.close();
                        resolve(k3);
                    });
                    relay.on('error', (err) => {
                        clearTimeout(timeout);
                        sub.unsub();
                        try { relay.close(); } catch(e){}
                        logToRelayOutput(`Relay error at ${relayUrl} while fetching Kind 3: ${err}`, 'ERROR');
                        reject(err);
                    });
                });
                relay.close();

                if (event) {
                    if (!latestKind3Event || event.created_at > latestKind3Event.created_at) {
                        latestKind3Event = event;
                    }
                }
            } catch (err) {
                 logToRelayOutput(`Failed to fetch Kind 3 from ${relayUrl}: ${err.message || err}`, 'WARN');
            }
        }

        if (latestKind3Event) {
            userFollows = latestKind3Event.tags.filter(tag => tag[0] === 'p').map(tag => tag[1]);
            logToRelayOutput(`Fetched ${userFollows.length} follows.`, 'INFO');
        } else {
            userFollows = [];
            logToRelayOutput('No Kind 3 (follows) event found.', 'WARN');
        }
        // TODO: Update UI if there's a follow count display
    }


    // --- UI UPDATES ---
    function clearUI() {
        // Reset profile sidebar
        profileBannerImg.src = 'img/default-banner.jpg';
        profileAvatarImg.src = 'img/default-avatar.png';
        profileNameElem.textContent = "Nom d'utilisateur";
        profileAboutElem.textContent = 'Description du profil...';
        statPostsElem.textContent = '0';
        // Reset detailed profile
        detailedProfileInfo.innerHTML = '<p>Connectez-vous pour voir votre profil.</p>';
        profileNpubDisplay.textContent = '';
        profileNprofileDisplay.textContent = '';
        profileNip05Display.textContent = '';
        // Clear N1/N2 wall
        messageFeedContent.innerHTML = '';
        // Clear forms, etc.
        profileForm.reset();
        newMessageForm.reset();
        // Clear relays
        relaysListElem.innerHTML = '<li>Connectez-vous pour voir les relais.</li>';
    }

    function updateProfileUI(profile) {
        profileNameElem.textContent = profile.name || profile.display_name || profile.username || `Anon (${(profile.pubkey || userPubKey || '').substring(0, 6)}...)`;
        profileAboutElem.textContent = profile.about || 'Aucune description.';
        profileAvatarImg.src = profile.picture || 'img/default-avatar.png';
        profileBannerImg.src = profile.banner || 'img/default-banner.jpg';
        // Update form editor placeholders too
        nameInput.value = profile.name || '';
        aboutInput.value = profile.about || '';
        pictureInput.value = profile.picture || '';
        bannerInput.value = profile.banner || '';
    }

    function updateDetailedProfileUI(profile) {
        const pubkeyToUse = profile.pubkey || userPubKey;
        if (!pubkeyToUse) {
            detailedProfileInfo.innerHTML = '<p>Impossible d\'afficher les détails du profil sans pubkey.</p>';
            return;
        }
        detailedProfileInfo.innerHTML = ''; // Clear previous

        profileNpubDisplay.textContent = `NPub: ${hexToBech32('npub', pubkeyToUse)}`;
        // Nprofile requires relays, more complex to generate on the fly here
        // profileNprofileDisplay.textContent = `NProfile: ${hexToBech32('nprofile', pubkeyToUse, relays)}`;
        profileNprofileDisplay.textContent = `NProfile: (Génération NIP-19 complexe)`;
        profileNip05Display.textContent = `NIP-05: ${profile.nip05 || 'Non vérifié'}`;

        const details = document.createElement('div');
        details.innerHTML = `
            <h4>Informations Brutes:</h4>
            <p><strong>Nom:</strong> ${profile.name || 'N/A'}</p>
            <p><strong>Nom Affiché:</strong> ${profile.display_name || 'N/A'}</p>
            <p><strong>À Propos:</strong></p><pre style="white-space: pre-wrap; word-break: break-all;">${profile.about || 'N/A'}</pre>
            <p><strong>Avatar URL:</strong> ${profile.picture || 'N/A'}</p>
            <p><strong>Bannière URL:</strong> ${profile.banner || 'N/A'}</p>
            <p><strong>Clé Publique (hex):</strong> ${pubkeyToUse}</p>
        `;
        detailedProfileInfo.appendChild(details);
    }


    function updateRelaysListUI() {
        relaysListElem.innerHTML = ''; // Clear existing
        if (relays.length === 0) {
            relaysListElem.innerHTML = '<li>Aucun relais configuré.</li>';
            return;
        }
        relays.forEach(relay => {
            const li = document.createElement('li');
            li.textContent = `${relay.url} (Read: ${relay.read ? '✓' : '✗'}, Write: ${relay.write ? '✓' : '✗'})`;
            // Add icons or better indicators later
            relaysListElem.appendChild(li);
        });
    }

    // --- PROFILE EDITING ---
    async function handleProfileUpdate(event) {
        event.preventDefault();
        if (!userPubKey || !window.nostr) {
            alert('Veuillez vous connecter d\'abord.');
            return;
        }

        const updatedProfile = {
            name: nameInput.value.trim(),
            about: aboutInput.value.trim(),
            picture: pictureInput.value.trim(),
            banner: bannerInput.value.trim(),
            // NIP-05 and other fields could be added here
        };

        const nostrEvent = {
            kind: 0,
            pubkey: userPubKey,
            created_at: Math.floor(Date.now() / 1000),
            tags: [], // No tags for basic Kind 0
            content: JSON.stringify(updatedProfile),
        };

        try {
            const signedEvent = await window.nostr.signEvent(nostrEvent);
            logToRelayOutput('Profil signé, publication en cours...', 'INFO');

            const writeRelays = getActiveWriteRelays();
            if (writeRelays.length === 0) {
                alert('Aucun relais en écriture configuré pour publier le profil.');
                logToRelayOutput('Aucun relais en écriture pour profil.', 'ERROR');
                return;
            }

            let publishedCount = 0;
            for (const relayUrl of writeRelays) {
                try {
                    const relay = nostrTools.relayInit(relayUrl);
                    await relay.connect();
                    await relay.publish(signedEvent);
                    relay.close();
                    logToRelayOutput(`Profil publié sur ${relayUrl}`, 'SUCCESS');
                    publishedCount++;
                } catch (pubErr) {
                    logToRelayOutput(`Échec de la publication du profil sur ${relayUrl}: ${pubErr.message || pubErr}`, 'ERROR');
                }
            }

            if (publishedCount > 0) {
                alert('Profil mis à jour avec succès sur ' + publishedCount + ' relais!');
                userProfile = { ...userProfile, ...updatedProfile }; // Update local cache
                updateProfileUI(userProfile);
                updateDetailedProfileUI(userProfile);
                navigateToSection('profile-section'); // Go back to profile view
            } else {
                alert('Échec de la mise à jour du profil sur tous les relais.');
            }

        } catch (signErr) {
            alert(`Erreur lors de la signature du profil: ${signErr.message || signErr}`);
            logToRelayOutput(`Erreur signature profil: ${signErr.message || signErr}`, 'ERROR');
        }
    }


    // --- MESSAGE HANDLING (N1/N2 WALL) ---
    // Cache for author profiles (Kind 0) to avoid re-fetching for every message
    const authorProfileCache = new Map();

    async function getAuthorProfile(pubkey) {
        if (authorProfileCache.has(pubkey)) {
            return authorProfileCache.get(pubkey);
        }
        // Simplified fetch, assuming relays are available
        const readRelays = getActiveReadRelays();
        if (readRelays.length === 0) return { name: pubkey.substring(0,6)+"..." }; // Fallback

        for (const relayUrl of readRelays.slice(0, 2)) { // Try first 2 relays for author profiles
             try {
                const relay = nostrTools.relayInit(relayUrl);
                await relay.connect();
                const sub = relay.sub([{ kinds: [0], authors: [pubkey], limit: 1 }]);
                const profile = await new Promise((resolve) => {
                    let p = null;
                    const t = setTimeout(() => { sub.unsub(); relay.close(); resolve({name: pubkey.substring(0,6)+"..."}); }, 2000);
                    sub.on('event', e => { clearTimeout(t); try {p = JSON.parse(e.content);} catch {} });
                    sub.on('eose', () => { clearTimeout(t); sub.unsub(); relay.close(); resolve(p || {name: pubkey.substring(0,6)+"..."}); });
                });
                relay.close();
                if (profile && profile.name) { // Basic check
                    authorProfileCache.set(pubkey, profile);
                    return profile;
                }
            } catch (e) { /* ignore */ }
        }
        const fallbackProfile = { name: pubkey.substring(0,6)+"...", picture: 'img/default-avatar.png' };
        authorProfileCache.set(pubkey, fallbackProfile); // Cache fallback
        return fallbackProfile;
    }


    async function renderMessage(event) {
        const authorData = await getAuthorProfile(event.pubkey);

        const messageDiv = document.createElement('div');
        messageDiv.className = 'message post-card'; // Use post-card style

        // Sanitize content simply for now
        const sanitizedContent = event.content
            .replace(/&/g, "&")
            .replace(/</g, "<")
            .replace(/>/g, ">")
            .replace(/"/g, "\"")
            .replace(/'/g, "'");

        // Basic URL linking
        const linkedContent = sanitizedContent.replace(
            /(https?:\/\/[^\s]+)/g,
            '<a href="$1" target="_blank" rel="noopener noreferrer">$1</a>'
        );


        messageDiv.innerHTML = `
            <div class="post-header">
                <img src="${authorData.picture || 'img/default-avatar.png'}" alt="avatar" class="post-avatar">
                <div>
                    <span class="post-author">${authorData.name || authorData.display_name || event.pubkey.substring(0, 10)}</span>
                    <span class="post-date">${new Date(event.created_at * 1000).toLocaleString()}</span>
                </div>
            </div>
            <div class="post-content">
                <p>${linkedContent}</p>
                ${/* TODO: Render images/videos if present in content/tags */''}
            </div>
            <div class="message-actions">
                <!-- Reply, Repost, Like buttons later -->
            </div>
        `;
        return messageDiv;
    }


    async function loadNostrWallMessages(initialLoad = false) {
        if (!userPubKey || userFollows.length === 0) {
            messageFeedContent.innerHTML = '<p>Suivez des personnes pour voir leurs messages ici.</p>';
            nostrFeedLoading.classList.add('hidden');
            loadMoreMessagesButton.classList.add('hidden');
            return;
        }

        logToRelayOutput('Chargement des messages du mur N1...', 'INFO');
        nostrFeedLoading.classList.remove('hidden');
        loadMoreMessagesButton.classList.add('hidden');
        messageFeedErrorElem.classList.add('hidden');
        noMoreMessagesElem.classList.add('hidden');


        const readRelays = getActiveReadRelays();
        if (readRelays.length === 0) {
            messageFeedErrorElem.textContent = 'Aucun relais en lecture configuré.';
            messageFeedErrorElem.classList.remove('hidden');
            nostrFeedLoading.classList.add('hidden');
            return;
        }

        const filter = {
            kinds: [1], // Text notes
            authors: userFollows, // N1: People current user follows
            limit: initialLoad ? 20 : 10, // Number of events to fetch
        };

        // For "load more", get events older than the oldest currently displayed
        if (!initialLoad && currentMessages.length > 0) {
            filter.until = currentMessages[currentMessages.length - 1].created_at -1; // -1 to avoid duplicate
        }

        const newEvents = [];
        const eventIds = new Set(currentMessages.map(e => e.id)); // To prevent duplicates

        // Subscribe to multiple relays
        const promises = readRelays.map(async (relayUrl) => {
            try {
                const relay = nostrTools.relayInit(relayUrl);
                await relay.connect();
                const sub = relay.sub([filter]); // Pass filter as an array element
                return new Promise((resolve) => {
                    const relayEvents = [];
                    const timeout = setTimeout(() => {
                        sub.unsub();
                        relay.close();
                        logToRelayOutput(`Timeout sur ${relayUrl} pour le mur.`, 'WARN');
                        resolve(relayEvents);
                    }, 8000); // 8s timeout for feed

                    sub.on('event', (event) => {
                        if (!eventIds.has(event.id)) {
                            relayEvents.push(event);
                            eventIds.add(event.id); // Add to set immediately
                        }
                    });
                    sub.on('eose', () => {
                        clearTimeout(timeout);
                        sub.unsub();
                        relay.close();
                        resolve(relayEvents);
                    });
                     relay.on('error', (err) => { // Added by me
                        clearTimeout(timeout);
                        sub.unsub();
                        try { relay.close(); } catch(e){}
                        logToRelayOutput(`Erreur relais ${relayUrl} pour le mur: ${err}`, 'ERROR');
                        resolve([]); // Resolve with empty on error for this relay
                    });
                });
            } catch (err) {
                logToRelayOutput(`Échec de connexion à ${relayUrl} pour le mur: ${err.message || err}`, 'ERROR');
                return []; // Return empty array if connection fails
            }
        });

        const results = await Promise.all(promises);
        results.forEach(relayEvs => newEvents.push(...relayEvs));

        // Sort all collected new events by creation date (newest first)
        newEvents.sort((a, b) => b.created_at - a.created_at);

        if (initialLoad) {
            currentMessages = []; // Clear for initial load
            messageFeedContent.innerHTML = ''; // Clear UI
        }

        if (newEvents.length === 0 && !initialLoad) {
            noMoreMessagesElem.classList.remove('hidden');
        } else if (newEvents.length > 0) {
            for (const event of newEvents) {
                currentMessages.push(event); // Add to overall list
                const messageElement = await renderMessage(event);
                messageFeedContent.appendChild(messageElement);
            }
            // Keep overall list sorted
            currentMessages.sort((a, b) => b.created_at - a.created_at);
        }


        nostrFeedLoading.classList.add('hidden');
        if (newEvents.length >= (filter.limit / readRelays.length)) { // Heuristic: if we got a decent amount, there might be more
             loadMoreMessagesButton.classList.remove('hidden');
        } else if (newEvents.length > 0 && newEvents.length < (filter.limit / readRelays.length) && !initialLoad) {
            noMoreMessagesElem.classList.remove('hidden'); // Probably no more
        } else if (initialLoad && newEvents.length === 0) {
             messageFeedContent.innerHTML = '<p>Aucun message trouvé pour les personnes que vous suivez.</p>';
        }

        statPostsElem.textContent = currentMessages.length; // Update post count roughly
    }

    // --- NEW MESSAGE POSTING ---
    async function handleNewMessageSubmit(event) {
        event.preventDefault();
        if (!userPubKey || !window.nostr) {
            alert('Veuillez vous connecter pour envoyer un message.');
            return;
        }
        const content = messageContentInput.value.trim();
        if (!content) {
            alert('Le message ne peut pas être vide.');
            return;
        }

        const nostrEvent = {
            kind: 1,
            pubkey: userPubKey,
            created_at: Math.floor(Date.now() / 1000),
            tags: [], // TODO: Add tags for replies, mentions, topics etc.
            content: content,
        };

        try {
            const signedEvent = await window.nostr.signEvent(nostrEvent);
            logToRelayOutput('Message signé, publication...', 'INFO');

            const writeRelays = getActiveWriteRelays();
            if (writeRelays.length === 0) {
                alert('Aucun relais en écriture configuré.');
                logToRelayOutput('Aucun relais en écriture pour message.', 'ERROR');
                return;
            }

            let publishedCount = 0;
            for (const relayUrl of writeRelays) {
                 try {
                    const relay = nostrTools.relayInit(relayUrl);
                    await relay.connect();
                    await relay.publish(signedEvent);
                    relay.close();
                    logToRelayOutput(`Message publié sur ${relayUrl}`, 'SUCCESS');
                    publishedCount++;
                } catch (pubErr) {
                    logToRelayOutput(`Échec publication message sur ${relayUrl}: ${pubErr.message || pubErr}`, 'ERROR');
                }
            }

            if (publishedCount > 0) {
                alert('Message envoyé avec succès sur ' + publishedCount + ' relais!');
                messageContentInput.value = ''; // Clear textarea
                // Optionally, add the new message to the top of the feed optimistically
                // Or trigger a reload of the feed. For now, let user refresh or wait.
                // await loadNostrWallMessages(true); // Refresh wall
                navigateToSection('n1n2-wall-section');
            } else {
                alert('Échec de l\'envoi du message sur tous les relais.');
            }

        } catch (signErr) {
            alert(`Erreur lors de la signature du message: ${signErr.message || signErr}`);
            logToRelayOutput(`Erreur signature message: ${signErr.message || signErr}`, 'ERROR');
        }
    }


    // --- UPLANET MAP ---
    async function initUPlanetMap() {
        if (leafletMap) return; // Already initialized

        logToRelayOutput('Initialisation de la carte UPlanet...', 'INFO');
        leafletMap = L.map(uplanetMapDiv).setView([46.603354, 1.888334], 5); // Default view (France)

        L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
            attribution: '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
        }).addTo(leafletMap);

        // Fetch and display Ustats markers
        try {
            // For robust fetching, use the same logic as UPlanet Terminal:
            const currentURL = new URL(window.location.href);
            const protocol = currentURL.protocol;
            const hostname = currentURL.hostname;
            let port = currentURL.port;
            var uHost = hostname.replace("ipfs.", "u.");
             if (port === "8080") { port = "54321"; }
             else if (port) { /* keep port */ }
             else { port = ""; }
            const UPlanetBase = protocol + "//" + uHost + (port ? (":" + port) : "");
            const UPlanetDataURL = UPlanetBase + '/';
            logToRelayOutput(`Fetching UPlanet data from: ${UPlanetDataURL}`, 'INFO');

            const response = await fetch(UPlanetDataURL);
            if (!response.ok) throw new Error(`HTTP error! status: ${response.status} for ${UPlanetDataURL}`);
            UPlanetData = await response.json();
            logToRelayOutput('Données UPlanet chargées.', 'INFO');
            addUPlanetMarkers();
        } catch (err) {
            logToRelayOutput(`Erreur chargement data json pour UPlanet: ${err.message || err}`, 'ERROR');
            uplanetMapDiv.innerHTML = `<p style="color:var(--color-error)">Impossible de charger les données de la carte UPlanet. (${err.message || err})</p>`;
        }
    }

    function addUPlanetMarkers() {
        if (!UPlanetData || !leafletMap) return;

        const playerIcon = L.icon({ // Example custom icon
            iconUrl: 'img/player-marker.png', // Provide your own marker image
            iconSize: [25, 41], iconAnchor: [12, 41], popupAnchor: [1, -34],
        });
        const umapIcon = L.icon({
            iconUrl: 'img/umap-marker.png', // Provide your own marker image
            iconSize: [25, 41], iconAnchor: [12, 41], popupAnchor: [1, -34],
        });

        if (UPlanetData.PLAYERs) {
            UPlanetData.PLAYERs.forEach(player => {
                if (player.LAT && player.LON && player.HEX && player.ASTROMAIL) {
                    const lat = parseFloat(player.LAT);
                    const lon = parseFloat(player.LON);
                    if (!isNaN(lat) && !isNaN(lon)) {
                        const marker = L.marker([lat, lon], { icon: playerIcon }).addTo(leafletMap);
                        // Updated link to use nostr.html or your actual profile page name
                        marker.bindPopup(`<b>Player:</b> ${player.ASTROMAIL}<br><a href="nostr.html?hex=${player.HEX}" target="_blank">Voir profil Nostr</a>`);
                    }
                }
            });
        }
        if (UPlanetData.UMAPs) {
            UPlanetData.UMAPs.forEach(umap => {
                if (umap.LAT && umap.LON && umap.UMAPHEX) {
                     const lat = parseFloat(umap.LAT);
                    const lon = parseFloat(umap.LON);
                     if (!isNaN(lat) && !isNaN(lon)) {
                        const marker = L.marker([lat, lon], { icon: umapIcon }).addTo(leafletMap);
                        let popupContent = `<b>UMAP</b><br>Lat: ${umap.LAT}, Lon: ${umap.LON}<br>`;
                        popupContent += `<a href="nostr.html?hex=${umap.UMAPHEX}" target="_blank">UMAP Nostr</a>`;
                        if(umap.UMAPROOT) {
                             popupContent += `<br><a href="/ipfs/${umap.UMAPROOT}" target="_blank">IPFS Drive</a>`;
                        }
                        marker.bindPopup(popupContent);
                    }
                }
            });
        }
         logToRelayOutput(`${(UPlanetData.PLAYERs?.length || 0) + (UPlanetData.UMAPs?.length || 0)} marqueurs ajoutés à la carte.`, 'INFO');
    }


    // --- UI EVENT HANDLERS ---
    connectButton.addEventListener('click', () => {
        if (userPubKey) {
            disconnectNostr();
        } else {
            connectNostr();
        }
    });

    darkModeToggle.addEventListener('click', () => {
        document.body.classList.toggle('dark-mode');
        darkModeToggle.textContent = document.body.classList.contains('dark-mode') ? '☀️' : '🌙';
        logToRelayOutput(`Mode Sombre ${document.body.classList.contains('dark-mode') ? 'Activé' : 'Désactivé'}`);
    });

    menuToggleButton.addEventListener('click', () => {
        appSidebar.style.display = appSidebar.style.display === 'block' ? 'none' : 'block';
    });

    contentMenuItems.forEach(item => {
        item.addEventListener('click', () => navigateToSection(item.dataset.section));
    });

    function navigateToSection(sectionId) {
        contentMenuItems.forEach(i => i.classList.remove('active'));
        document.querySelector(`.menu-item[data-section="${sectionId}"]`)?.classList.add('active');

        contentSections.forEach(s => s.classList.add('hidden'));
        const targetSection = document.getElementById(sectionId);
        if (targetSection) {
            targetSection.classList.remove('hidden');
            logToRelayOutput(`Navigation vers la section: ${sectionId}`, 'DEBUG');

            if (sectionId === 'uplanet-feed' && !leafletMap) {
                initUPlanetMap();
            }
            if (sectionId === 'n1n2-wall-section' && currentMessages.length === 0 && userPubKey && userFollows.length > 0) {
                loadNostrWallMessages(true); // Initial load if navigating to empty wall
            }
        } else {
            logToRelayOutput(`Section ${sectionId} non trouvée.`, 'ERROR');
        }
    }

    // Initial active section (e.g., profile)
    if (viewProfileLink) { // Link from sidebar profile card
        viewProfileLink.addEventListener('click', (e) => {
            e.preventDefault();
            navigateToSection('profile-section');
        });
    }
    if(editProfileButton) { // Button in sidebar profile card
        editProfileButton.addEventListener('click', () => navigateToSection('profile-editor'));
    }


    profileForm.addEventListener('submit', handleProfileUpdate);
    cancelProfileEditButton.addEventListener('click', () => navigateToSection('profile-section'));

    newMessageForm.addEventListener('submit', handleNewMessageSubmit);

    loadMoreMessagesButton.addEventListener('click', () => loadNostrWallMessages(false));


    // --- INITIALIZATION ---
    function initApp() {
        logToRelayOutput('Application initialisée.', 'INFO');
        updateConnectionStatus(false); // Default to disconnected
        navigateToSection('profile-section'); // Default section
        // Try to auto-connect if previously connected or extension allows
        // For simplicity, require manual connect for now.
    }

    initApp();
});
