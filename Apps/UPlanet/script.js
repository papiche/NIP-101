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

    let publicKey = null;
    let relays = [];
    let isConnected = false; // Track connection status
    let isDarkMode = false; // Track dark mode state
    const defaultRelaysUrls = ["wss://relay.copylaradio.com", "wss://relay.g1sms.fr", "ws://127.0.0.1:7777"];

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
        // ... (Remplacer par code Nostr pour récupérer kind 0)
        const exampleProfile = { // Profil statique pour l'exemple
            name: "Utilisateur Nostr Exemple",
            about: "Profil de démonstration UPlanet NOSTR App.",
            picture: "img/default-avatar.png",
            banner: "img/default-banner.jpg",
            postsCount: 123 // Exemple de statistique
        };
        displayProfile(exampleProfile);
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


    // --- Initialisation ---
    updateConnectionStatus(false, "Déconnecté"); // État initial déconnecté
    fetchUPlanetPosts();
});

