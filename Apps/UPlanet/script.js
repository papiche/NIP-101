// script.js
document.addEventListener('DOMContentLoaded', () => {
    const connectButton = document.getElementById('connect-button');
    const relaysList = document.getElementById('relays-list');
    const profileName = document.getElementById('profile-name');
    const profileAbout = document.getElementById('profile-about');
    const profileBannerImg = document.getElementById('profile-banner-img');
    const profileAvatarImg = document.getElementById('profile-avatar-img');
    const editProfileButton = document.getElementById('edit-profile-button');
    const profileEditorSection = document.getElementById('profile-editor');
    const profileForm = document.getElementById('profile-form');
    const cancelProfileEditButton = document.getElementById('cancel-profile-edit');
    const newMessageForm = document.getElementById('new-message-form');
    const messageContentInput = document.getElementById('message-content');
    const imageUploadInput = document.getElementById('image-upload');
    const uplanetPostsDiv = document.getElementById('uplanet-posts');
    const relayLogsOutput = document.getElementById('relay-logs-output');
    const menuItems = document.querySelectorAll('.content-menu .menu-item');
    const sections = document.querySelectorAll('.app-main-content > .content-section');
    const connectionBadge = document.getElementById('connection-badge');
    const statusIndicator = document.getElementById('status-indicator');
    const connectionText = document.getElementById('connection-text');
    const darkModeToggle = document.getElementById('dark-mode-toggle');
    const appSidebar = document.getElementById('app-sidebar');
    const menuToggleButton = document.getElementById('menu-toggle-button');
    const messagePreviewSection = document.getElementById('message-preview');
    const messagePreviewContent = document.getElementById('message-preview-content');
    const messagePreviewImage = document.getElementById('message-preview-image');
    const filterDistanceSelect = document.getElementById('filter-distance');
    const uplanetMapDiv = document.getElementById('uplanet-map'); // Div pour la carte Leaflet
    const detailedProfileInfoDiv = document.getElementById('detailed-profile-info'); // Div pour le profil détaillé
    const profileNpubDisplay = document.getElementById('profile-npub-display');
    const profileNprofileDisplay = document.getElementById('profile-nprofile-display');
    const profileNip05Display = document.getElementById('profile-nip05-display');
    const nostrFeedLoading = document.getElementById('nostr-feed-loading');
    const messageFeedContentDiv = document.getElementById('message-feed-content');
    const loadMoreMessagesButton = document.getElementById('load-more-messages');
    const noMoreMessagesParagraph = document.getElementById('no-more-messages');
    const messageFeedErrorParagraph = document.getElementById('message-feed-error');


    let publicKey = null;
    let relays = [];
    let isConnected = false; // Track connection status
    let isDarkMode = false; // Track dark mode state
    const defaultRelaysUrls = ["wss://relay.copylaradio.com", "wss://relay.g1sms.fr", "ws://127.0.0.1:7777"];
    let userProfileData = null; // Variable pour stocker les données de profil
    let nostrMessages = []; // Stocker les messages Nostr N1/N2
    let oldestCreatedAt = null; // Pagination des messages Nostr
    let isLoadingMessages = false; // Pour éviter de charger plusieurs pages à la fois

    // --- Dark Mode Toggle ---
    darkModeToggle.addEventListener('click', () => {
        isDarkMode = !isDarkMode;
        document.body.classList.toggle('dark-mode', isDarkMode);
        darkModeToggle.textContent = isDarkMode ? '☀️' : '🌙'; // Change icon
        // Sauvegarder le mode sombre dans localStorage (optionnel)
        localStorage.setItem('darkMode', isDarkMode);
    });
    // Charger le mode sombre sauvegardé ou par défaut (clair)
    const savedDarkMode = localStorage.getItem('darkMode');
    if (savedDarkMode === 'true') {
        isDarkMode = true;
        document.body.classList.add('dark-mode');
        darkModeToggle.textContent = '☀️';
    }

    // --- Menu Toggle (Mobile) ---
    menuToggleButton.addEventListener('click', () => {
        appSidebar.style.display = appSidebar.style.display === 'block' ? 'none' : 'block';
    });

    // --- Menu Navigation ---
    menuItems.forEach(menuItem => {
        menuItem.addEventListener('click', () => {
            const sectionId = menuItem.dataset.section;
            showSection(sectionId);
        });
    });

    function showSection(sectionId) {
        sections.forEach(section => section.classList.add('hidden'));
        menuItems.forEach(item => item.classList.remove('active'));

        const sectionToShow = document.getElementById(sectionId);
        const menuItemToActivate = document.querySelector(`.content-menu .menu-item[data-section="${sectionId}"]`);

        if (sectionToShow) sectionToShow.classList.remove('hidden');
        if (menuItemToActivate) menuItemToActivate.classList.add('active');
        if (appSidebar.style.display === 'block' && window.innerWidth < 768) {
            appSidebar.style.display = 'none'; // Cacher la sidebar après navigation sur mobile
        }
        if (sectionId === 'uplanet-feed') {
            fetchUPlanetPosts(); // Charger les posts UPlanet quand section active
        }
        if (sectionId === 'n1n2-wall-section') {
            loadInitialNostrMessages(); // Charger les messages N1/N2 quand section active
        }
    }
    showSection('profile-section');


    // --- NOSTR CONNECT ---
    connectButton.addEventListener('click', async () => {
        if (window.nostr) {
            try {
                updateConnectionStatus(true, "Connexion..."); // Indicateur de chargement
                publicKey = await window.nostr.getPublicKey();
                console.log("Public Key récupérée via Nostr Connect:", publicKey);
                updateConnectionStatus(true, "Connecté"); // Indicateur Connecté
                connectButton.textContent = 'Connecté';
                connectButton.disabled = true;
                fetchProfileAndRelays();
            } catch (error) {
                console.error("Erreur Nostr Connect:", error);
                updateConnectionStatus(false, "Erreur"); // Indicateur Erreur
                alert("Erreur lors de la connexion avec Nostr Connect.");
            }
        } else {
            alert("Nostr Connect non détecté. Veuillez installer l'extension.");
            updateConnectionStatus(false, "Non détecté"); // Indicateur Non détecté
        }
    });

    function updateConnectionStatus(connected, text) {
        isConnected = connected;
        connectionBadge.classList.toggle('connected', connected);
        statusIndicator.style.backgroundColor = connected ? 'green' : 'gray';
        connectionText.textContent = text;
    }

    async function fetchProfileAndRelays() {
        if (!publicKey) return;

        // 1. Récupérer les Relais Favoris (Kind 10002)
        console.log("Récupération des relais favoris (kind 10002)...");
        relaysList.innerHTML = '<li>Chargement...</li>';
        // ... (Remplacer par code Nostr pour récupérer kind 10002)
        displayRelays(defaultRelaysUrls); // Relais par défaut pour l'instant

        // 2. Récupérer le Profil (Kind 0)
        console.log("Récupération du profil (kind 0)...");
        fetchNostrProfile(publicKey);
    }

    async function fetchNostrProfile(pubkey) {
        const relayPool = new nostrTools.SimplePool();
        let profileData = null;

        try {
            const profileEvent = await relayPool.get(defaultRelaysUrls, { // Utiliser les relais par défaut ou favoris
                kinds: [0],
                authors: [pubkey]
            });

            if (profileEvent && profileEvent.content) {
                profileData = JSON.parse(profileEvent.content);
                userProfileData = profileData; // Stocker les données du profil
                displayProfile(profileData); // Afficher dans la sidebar
                displayDetailedProfile(profileEvent, pubkey); // Afficher les détails dans la section profil
            } else {
                profileName.textContent = "Profil Inconnu";
                profileAbout.textContent = "Aucune info de profil trouvée.";
            }
        } catch (error) {
            console.error("Erreur lors de la récupération du profil Nostr:", error);
            profileName.textContent = "Erreur Profil";
            profileAbout.textContent = "Erreur de chargement du profil.";
        } finally {
            relayPool.close(defaultRelaysUrls);
        }
    }

    function displayDetailedProfile(profileEvent, pubkey) {
        if (!profileEvent) {
            detailedProfileInfoDiv.innerHTML = "<p>Profil Nostr non trouvé.</p>";
            return;
        }

        const profileData = JSON.parse(profileEvent.content);
        profileName.textContent = profileData.name || "Nom Inconnu"; // Sidebar name update
        profileAbout.textContent = profileData.about || "Aucune description."; // Sidebar about update
        profileBannerImg.src = profileData.banner || "img/default-banner.jpg"; // Sidebar banner update
        profileAvatarImg.src = profileData.picture || "img/default-avatar.png"; // Sidebar avatar update


        profileNpubDisplay.innerHTML = `<p><b>npub:</b> ${nostrTools.nip19.npubEncode(pubkey)}</p>`;
        profileNprofileDisplay.innerHTML = `<p><b>nprofile:</b> ${nostrTools.nip19.nprofileEncode({ pubkey: pubkey, relays: defaultRelaysUrls })}</p>`; // Exemple avec relais par défaut
        profileNip05Display.innerHTML = `<p><b>nip05:</b> ${profileData.nip05 || 'Non défini'}</p>`;
        // ... afficher d'autres détails à partir de profileData dans detailedProfileInfoDiv ...
    }


    function displayRelays(relayUrls) {
        relaysList.innerHTML = '';
        if (relayUrls && relayUrls.length > 0) {
            relayUrls.forEach(relayUrl => {
                const li = document.createElement('li');
                li.textContent = relayUrl;
                relaysList.appendChild(li);
            });
        } else {
            relaysList.innerHTML = '<li>Aucun relais favori.</li>';
        }
        relays = relayUrls;
    }

    function displayProfile(profileData) {
        profileName.textContent = profileData.name || "Nom Inconnu";
        profileAbout.textContent = profileData.about || "Aucune description.";
        profileBannerImg.src = profileData.banner || "img/default-banner.jpg";
        profileAvatarImg.src = profileData.picture || "img/default-avatar.png";
        document.getElementById('stat-posts').textContent = profileData.postsCount || 0; // Afficher les stats
        // document.getElementById('stat-followers').textContent = profileData.followersCount || 0; // ...
    }

    // --- EDITION DE PROFIL ---
    editProfileButton.addEventListener('click', () => showSection('profile-editor'));
    cancelProfileEditButton.addEventListener('click', () => showSection('profile-section'));

    profileForm.addEventListener('submit', async (event) => {
        event.preventDefault();
        // ... (Gestion soumission formulaire profil - inchangé)
    });


    // --- NOUVEAU MESSAGE (Kind 1 avec image et GPS) ---
    newMessageForm.addEventListener('submit', async (event) => {
        event.preventDefault();
        // ... (Gestion soumission nouveau message - inchangé)
    });

    // --- Message Preview ---
    messageContentInput.addEventListener('input', () => {
        const text = messageContentInput.value;
        const image = imageUploadInput.files[0];

        if (text || image) {
            messagePreviewSection.classList.remove('hidden');
            messagePreviewContent.textContent = text; // Afficher le texte
            if (image) {
                const reader = new FileReader();
                reader.onload = (e) => {
                    messagePreviewImage.src = e.target.result;
                    messagePreviewImage.classList.remove('hidden');
                }
                reader.readAsDataURL(image);
            } else {
                messagePreviewImage.classList.add('hidden'); // Cacher image si pas d'image
                messagePreviewImage.src = ""; // Réinitialiser la source
            }
        } else {
            messagePreviewSection.classList.add('hidden'); // Cacher si vide
        }
    });
    imageUploadInput.addEventListener('change', () => { // Mettre à jour preview si image change
        messageContentInput.dispatchEvent(new Event('input')); // Déclencher l'événement 'input' sur le textarea
    });


    function getGeolocation() {
        // ... (Fonction getGeolocation - inchangée)
    }

    // --- UPlanet Feed ---
    let uplanetMap; // Variable pour la carte Leaflet
    function initUPlanetMap() {
        if (!uplanetMap) { // Initialiser la carte une seule fois
            uplanetMap = L.map('uplanet-map').setView([43.6043, 1.4437], 13); // Toulouse par défaut
            L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
                attribution: '© <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
            }).addTo(uplanetMap);
            // ... (Ajouter des marqueurs, etc. plus tard) ...
        }
    }

    async function fetchUPlanetPosts() {
        console.log("Récupération des posts UPlanet...");
        uplanetPostsDiv.innerHTML = 'Chargement des posts UPlanet...';
        initUPlanetMap(); // Initialiser la carte Leaflet ici

        let currentGPS = null;
        try {
            currentGPS = await getGeolocation();
            console.log("Position GPS pour UPlanet:", currentGPS);
            if (currentGPS) {
                uplanetMap.setView([currentGPS.latitude, currentGPS.longitude], 13); // Centrer la carte sur la position
            }
        } catch (error) {
            console.warn("Géolocalisation non disponible pour UPlanet:", error);
            uplanetPostsDiv.innerHTML = 'Géolocalisation non disponible. Flux UPlanet basé sur Toulouse.';
            // Laisser la carte centrée sur Toulouse par défaut
        }

        // ... (Remplacer par code pour découvrir clés UPlanet et récupérer les posts)
        const examplePosts = [ // Posts statiques pour l'exemple
            { author: "@uplanet1", content: "Message UPlanet 1...", imageUrl: "img/placeholder-image.jpg", date: new Date(), location: [43.6043, 1.4437] }, // Toulouse
            { author: "@uplanet2", content: "Message UPlanet 2...", imageUrl: null, date: new Date(), location: [43.55, 1.40] } // Légèrement décentré
        ];
        displayUPlanetPosts(examplePosts);
    }

    function displayUPlanetPosts(posts) {
        uplanetPostsDiv.innerHTML = '';
        if (posts && posts.length > 0) {
            posts.forEach(postData => {
                const postElement = createUPlanetPostElement(postData);
                uplanetPostsDiv.appendChild(postElement);
                if (uplanetMap && postData.location) {
                    L.marker(postData.location).bindPopup(`<b>${postData.author}</b><br>${postData.content.substring(0, 50)}...`).addTo(uplanetMap); // Ajouter marqueur sur la carte
                }
            });
        } else {
            uplanetPostsDiv.innerHTML = 'Aucun post UPlanet à afficher.';
        }
    }

    function createUPlanetPostElement(postData) {
        const postCard = document.createElement('div');
        postCard.classList.add('post-card');

        const headerElement = document.createElement('div');
        headerElement.classList.add('post-header');
        headerElement.innerHTML = `
            <img src="img/default-avatar.png" alt="Avatar" class="post-avatar">
            <span class="post-author">${postData.author}</span>
            <span class="post-date">${formatDate(postData.date)}</span>
        `;
        postCard.appendChild(headerElement);

        const contentElement = document.createElement('div');
        contentElement.classList.add('post-content');
        contentElement.innerHTML = `<p>${postData.content}</p>`;
        if (postData.imageUrl) {
            contentElement.innerHTML += `<img src="${postData.imageUrl}" alt="Image jointe" class="post-image">`;
        }
        postCard.appendChild(contentElement);
        return postCard;
    }


    function formatDate(date) {
        // Fonction simple pour formater la date (à améliorer)
        const now = new Date();
        const diffInMinutes = Math.round((now - date) / (1000 * 60));
        if (diffInMinutes < 60) {
            return `Il y a ${diffInMinutes} minutes`;
        } else if (diffInMinutes < 24 * 60) {
            return `Il y a ${Math.round(diffInMinutes / 60)} heures`;
        } else {
            return date.toLocaleDateString();
        }
    }


    // --- LOGS RELAIS ---
    function logRelayMessage(message) {
        const timestamp = new Date().toLocaleTimeString();
        relayLogsOutput.value += `[${timestamp}] ${message}\n`;
        relayLogsOutput.scrollTop = relayLogsOutput.scrollHeight; // Scroll to bottom
    }

    logRelayMessage("Application UPlanet NOSTR démarrée..."); // Log au démarrage


    // --- NOSTR N1/N2 MESSAGE FEED ---
    async function loadInitialNostrMessages() {
        if (isLoadingMessages) return;
        isLoadingMessages = true;
        nostrFeedLoading.classList.remove('hidden');
        messageFeedErrorParagraph.classList.add('hidden');
        messageFeedContentDiv.innerHTML = ''; // Clear existing messages
        noMoreMessagesParagraph.classList.add('hidden');
        loadMoreMessagesButton.classList.add('hidden');

        try {
            const relayPool = new nostrTools.SimplePool();
            const filter = {
                kinds: [1], // N1/N2 notes (text notes)
                limit: 20, // Initial load limit
                authors: [publicKey] // Filtrer par l'utilisateur connecté - à adapter si besoin
            };
            const events = await relayPool.list(defaultRelaysUrls, [filter]); // Utiliser les relais par défaut
            relayPool.close(defaultRelaysUrls);

            if (events && events.length > 0) {
                nostrMessages = events.sort((a, b) => b.created_at - a.created_at); // Sort by newest
                oldestCreatedAt = nostrMessages[nostrMessages.length - 1].created_at;
                displayNostrMessages(nostrMessages);
                if (events.length >= filter.limit) { // Show "Load More" if limit reached
                    loadMoreMessagesButton.classList.remove('hidden');
                }
            } else {
                messageFeedContentDiv.innerHTML = '<p>Aucun message Nostr trouvé.</p>';
                noMoreMessagesParagraph.classList.remove('hidden'); // "No messages" message
            }
        } catch (error) {
            console.error("Error loading Nostr messages:", error);
            messageFeedErrorParagraph.textContent = "Erreur de chargement des messages Nostr.";
            messageFeedErrorParagraph.classList.remove('hidden');
        } finally {
            nostrFeedLoading.classList.add('hidden');
            isLoadingMessages = false;
        }
    }

    loadMoreMessagesButton.addEventListener('click', loadMoreNostrMessages); // Listener pour "Charger Plus"

    async function loadMoreNostrMessages() {
        if (isLoadingMessages || !oldestCreatedAt) return; // Prevent concurrent loading
        isLoadingMessages = true;
        loadMoreMessagesButton.disabled = true; // Désactiver le bouton pendant le chargement
        messageFeedErrorParagraph.classList.add('hidden'); // Cacher les erreurs précédentes

        try {
            const relayPool = new nostrTools.SimplePool();
            const filter = {
                kinds: [1],
                limit: 10, // Charger plus de messages à chaque fois
                authors: [publicKey], // Filtrer par l'utilisateur connecté
                until: oldestCreatedAt // Charger les messages plus anciens
            };
            const events = await relayPool.list(defaultRelaysUrls, [filter]);
            relayPool.close(defaultRelaysUrls);

            if (events && events.length > 0) {
                const newMessages = events.sort((a, b) => b.created_at - a.created_at);
                nostrMessages = nostrMessages.concat(newMessages); // Ajouter les nouveaux messages
                oldestCreatedAt = newMessages[newMessages.length - 1].created_at; // Update oldest timestamp
                displayNostrMessages(newMessages); // Afficher seulement les nouveaux messages
                if (events.length < filter.limit) { // Hide "Load More" if no more messages
                    loadMoreMessagesButton.classList.add('hidden');
                    noMoreMessagesParagraph.classList.remove('hidden'); // Afficher "Plus de messages"
                }
            } else {
                loadMoreMessagesButton.classList.add('hidden'); // Cacher "Charger Plus" si pas de nouveaux messages
                noMoreMessagesParagraph.classList.remove('hidden'); // Afficher "Plus de messages"
            }
        } catch (error) {
            console.error("Error loading more Nostr messages:", error);
            messageFeedErrorParagraph.textContent = "Erreur lors du chargement de plus de messages.";
            messageFeedErrorParagraph.classList.remove('hidden');
        } finally {
            isLoadingMessages = false;
            loadMoreMessagesButton.disabled = false; // Réactiver le bouton
        }
    }


    function displayNostrMessages(messagesToDisplay) {
        messagesToDisplay.forEach(message => {
            const messageDiv = createNostrMessageElement(message);
            messageFeedContentDiv.prepend(messageDiv); // Ajouter au début pour ordre chronologique inverse
        });
    }

    function createNostrMessageElement(message) {
        const messageCard = document.createElement('div');
        messageCard.classList.add('message');

        const headerDiv = document.createElement('div');
        headerDiv.classList.add('message-header');

        const authorDiv = document.createElement('div');
        authorDiv.classList.add('message-author');
        authorDiv.textContent = `Publié le ${formatDate(new Date(message.created_at * 1000))}`; // Format date

        headerDiv.appendChild(authorDiv);
        messageCard.appendChild(headerDiv);

        const contentDiv = document.createElement('div');
        contentDiv.classList.add('message-content');
        contentDiv.innerHTML = formatNostrContent(message); // Format content (liens, mentions)
        messageCard.appendChild(contentDiv);

        return messageCard;
    }

    function formatNostrContent(message) {
        let content = message.content;
        let formattedContent = content;

        // Liens cliquables
        formattedContent = formattedContent.replace(/(https?:\/\/[^\s]+)/g, '<a href="$1" target="_blank" rel="noopener noreferrer">$1</a>');

        // Mentions #[index] → tag 'p'
        formattedContent = formattedContent.replace(/#\[(\d+)]/g, (match, index) => {
            const tag = message.tags?.[parseInt(index)];
            if (tag && tag[0] === 'p') {
                const pubkey = tag[1];
                const npub = nostrTools.nip19.npubEncode(pubkey);
                return `<a href="https://nostr.band/${npub}" target="_blank" rel="noopener noreferrer">@${npub.slice(0, 8)}...</a>`;
            }
            return match;
        });

        return formattedContent;
    }


    // --- Initialisation ---
    updateConnectionStatus(false, "Déconnecté"); // État initial déconnecté
    fetchUPlanetPosts();
});
