document.addEventListener('DOMContentLoaded', () => {
    const connectButton = document.getElementById('connect-button');
    const relaysList = document.getElementById('relays-list');
    const profileName = document.getElementById('profile-name');
    const profileAbout = document.getElementById('profile-about');
    const editProfileButton = document.getElementById('edit-profile-button');
    const profileEditorSection = document.getElementById('profile-editor');
    const profileForm = document.getElementById('profile-form');
    const cancelProfileEditButton = document.getElementById('cancel-profile-edit');
    const newMessageForm = document.getElementById('new-message-form');
    const messageContentInput = document.getElementById('message-content');
    const imageUploadInput = document.getElementById('image-upload');
    const uplanetPostsDiv = document.getElementById('uplanet-posts');
    const relayLogsOutput = document.getElementById('relay-logs-output'); // Logs area
    const menuItems = document.querySelectorAll('.menu-item'); // Menu items
    const sections = document.querySelectorAll('main > section'); // All main sections

    let publicKey = null;
    let relays = [];
    const defaultRelaysUrls = ["wss://relay.copylaradio.com", "wss://relay.g1sms.fr", "ws://127.0.0.1:7777"]; // Default relays

    // --- Menu Navigation ---
    menuItems.forEach(menuItem => {
        menuItem.addEventListener('click', () => {
            const sectionId = menuItem.dataset.section;
            showSection(sectionId);
        });
    });

    function showSection(sectionId) {
        sections.forEach(section => {
            section.classList.add('hidden'); // Hide all sections
        });
        menuItems.forEach(item => {
            item.classList.remove('active'); // Deactivate all menu items
        });

        const sectionToShow = document.getElementById(sectionId);
        const menuItemToActivate = document.querySelector(`.menu-item[data-section="${sectionId}"]`);

        if (sectionToShow) {
            sectionToShow.classList.remove('hidden'); // Show selected section
        }
        if (menuItemToActivate) {
            menuItemToActivate.classList.add('active'); // Activate selected menu item
        }
    }
    // Initially show profile section
    showSection('profile-section');


    // --- NOSTR CONNECT ---
    connectButton.addEventListener('click', async () => {
        if (window.nostr) {
            try {
                publicKey = await window.nostr.getPublicKey();
                console.log("Public Key récupérée via Nostr Connect:", publicKey);
                connectButton.textContent = 'Connecté';
                connectButton.disabled = true;
                fetchProfileAndRelays();
            } catch (error) {
                console.error("Erreur Nostr Connect:", error);
                alert("Erreur lors de la connexion avec Nostr Connect.");
            }
        } else {
            alert("Nostr Connect n'est pas détecté. Veuillez installer l'extension.");
        }
    });

    async function fetchProfileAndRelays() {
        if (!publicKey) return;

        // 1. Récupérer les Relais Favoris (Kind 10002)
        console.log("Récupération des relais favoris (kind 10002)...");
        relaysList.innerHTML = '<li>Chargement des relais...</li>';

        // --- ICI :  CODE POUR RÉCUPÉRER KIND 10002 (Utiliser une librairie Nostr JS) ---
        // Pour l'instant, relais par défaut si pas de récupération (à remplacer par fetch Nostr)
        displayRelays(defaultRelaysUrls);


        // 2. Récupérer le Profil (Kind 0)
        console.log("Récupération du profil (kind 0)...");
        // --- ICI : CODE POUR RÉCUPÉRER KIND 0 (Utiliser une librairie Nostr JS) ---
        // Pour l'instant, profil statique pour l'exemple
        const exampleProfile = {
            name: "Utilisateur Nostr",
            about: "Ceci est un profil de démonstration.",
            picture: "img/default-avatar.png"
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
            relaysList.innerHTML = '<li>Aucun relais favori trouvé.</li>';
        }
        relays = relayUrls;
    }

    function displayProfile(profileData) {
        profileName.textContent = profileData.name || "Nom inconnu";
        profileAbout.textContent = profileData.about || "Aucune description.";
        const avatarImg = document.querySelector('.profile-card .avatar');
        if (profileData.picture) {
            avatarImg.src = profileData.picture;
        } else {
            avatarImg.src = 'img/default-avatar.png';
        }
    }

    // --- EDITION DE PROFIL ---
    editProfileButton.addEventListener('click', () => {
        profileEditorSection.classList.remove('hidden'); // Afficher la section d'édition
        // Pré-remplir le formulaire avec les données de profil actuelles (si disponibles)
        // ... (à implémenter)
    });

    cancelProfileEditButton.addEventListener('click', () => {
        profileEditorSection.classList.add('hidden'); // Cacher la section d'édition
    });

    profileForm.addEventListener('submit', async (event) => {
        event.preventDefault(); // Empêcher la soumission par défaut

        const name = document.getElementById('name').value;
        const about = document.getElementById('about').value;
        const pictureUrl = document.getElementById('picture').value;
        const bannerUrl = document.getElementById('banner').value;

        const metadata = {
            name: name,
            about: about,
            picture: pictureUrl,
            banner: bannerUrl,
            // ... autres champs de metadata ...
        };

        const content = JSON.stringify(metadata);
        const eventToPublish = {
            kind: 0, // Kind 0 pour le profil (metadata)
            content: content,
            created_at: Math.floor(Date.now() / 1000),
            pubkey: publicKey, // Public key de l'utilisateur connecté
            tags: [], // Tags supplémentaires si nécessaire
        };

        if (window.nostr && publicKey) {
            try {
                const signedEvent = await window.nostr.signEvent(eventToPublish);
                console.log("Événement signé:", signedEvent);
                // --- ICI : CODE POUR PUBLIER L'ÉVÉNEMENT SIGNÉ SUR LES RELAIS (Utiliser une librairie Nostr JS) ---
                // Exemple conceptuel (à remplacer par du vrai code Nostr) :
                // await publishEventToRelays(relays, signedEvent); // Fonction fictive
                alert("Profil mis à jour avec succès !");
                profileEditorSection.classList.add('hidden'); // Cacher l'éditeur après la sauvegarde
                fetchProfileAndRelays(); // Refetch le profil mis à jour pour l'afficher dans la sidebar
            } catch (error) {
                console.error("Erreur lors de la signature ou publication de l'événement:", error);
                alert("Erreur lors de la mise à jour du profil.");
            }
        } else {
            alert("Non connecté à Nostr Connect ou public key manquante.");
        }
    });


    // --- NOUVEAU MESSAGE (Kind 1 avec image et GPS) ---
    newMessageForm.addEventListener('submit', async (event) => {
        event.preventDefault();

        const messageContent = messageContentInput.value;
        const imageFile = imageUploadInput.files[0];

        if (!messageContent && !imageFile) {
            alert("Veuillez écrire un message ou choisir une image.");
            return;
        }

        let imageUrl = null;
        if (imageFile) {
            // --- NIP-96 : Uploader l'image sur g1sms.fr et récupérer l'URL ---
            console.log("Upload de l'image sur g1sms.fr (NIP-96)...");
            // --- ICI : CODE D'UPLOAD NIP-96 (Utiliser Fetch API et g1sms.fr) ---
            // Exemple conceptuel (à remplacer par du vrai code NIP-96) :
            // imageUrl = await uploadImageToG1SMS(imageFile); // Fonction fictive
            imageUrl = "img/placeholder-image.jpg"; // URL statique pour l'exemple
            console.log("URL de l'image uploadée:", imageUrl);
        }

        // --- Géolocalisation (GPS) ---
        let gpsCoordinates = null;
        try {
            gpsCoordinates = await getGeolocation(); // Fonction pour obtenir la géolocalisation
            console.log("Coordonnées GPS:", gpsCoordinates);
        } catch (error) {
            console.warn("Géolocalisation non disponible ou refusée:", error);
            // La géolocalisation est optionnelle, continuer sans si erreur
        }


        const tags = [];
        if (imageUrl) {
            tags.push(["url", imageUrl]); // Tag 'url' pour l'image (NIP-94 - simple URL)
            // Pour NIP-96 complet, il faudrait ajouter des tags plus spécifiques
        }
        if (gpsCoordinates) {
            tags.push(["geo", `${gpsCoordinates.latitude};${gpsCoordinates.longitude}`]); // Tag 'geo' pour GPS
        }

        const eventToPublish = {
            kind: 1, // Kind 1 pour un message texte (note)
            content: messageContent,
            created_at: Math.floor(Date.now() / 1000),
            pubkey: publicKey,
            tags: tags,
        };

        if (window.nostr && publicKey) {
            try {
                const signedEvent = await window.nostr.signEvent(eventToPublish);
                console.log("Événement signé:", signedEvent);
                // --- ICI : CODE POUR PUBLIER L'ÉVÉNEMENT SIGNÉ SUR LES RELAIS (Utiliser une librairie Nostr JS) ---
                // Exemple conceptuel (à remplacer par du vrai code Nostr) :
                // await publishEventToRelays(relays, signedEvent); // Fonction fictive
                alert("Message envoyé !");
                newMessageForm.reset(); // Réinitialiser le formulaire
            } catch (error) {
                console.error("Erreur lors de la signature ou publication du message:", error);
                alert("Erreur lors de l'envoi du message.");
            }
        } else {
            alert("Non connecté à Nostr Connect ou public key manquante.");
        }
    });

    function getGeolocation() {
        return new Promise((resolve, reject) => {
            if (navigator.geolocation) {
                navigator.geolocation.getCurrentPosition(
                    position => {
                        resolve({
                            latitude: position.coords.latitude,
                            longitude: position.coords.longitude
                        });
                    },
                    error => {
                        reject(error);
                    }
                );
            } else {
                reject("Géolocalisation non supportée par le navigateur.");
            }
        });
    }


    // --- FLUX UPLANET (Géolocalisation) ---
    async function fetchUPlanetPosts() {
        console.log("Récupération des posts UPlanet...");
        uplanetPostsDiv.innerHTML = 'Chargement des posts UPlanet...';

        let currentGPS = null;
        try {
            currentGPS = await getGeolocation();
            console.log("Position GPS pour UPlanet:", currentGPS);
        } catch (error) {
            console.warn("Géolocalisation non disponible pour UPlanet:", error);
            uplanetPostsDiv.innerHTML = 'Géolocalisation non disponible. Impossible de charger le flux UPlanet.';
            return;
        }

        // --- ICI : CODE POUR DÉCOUVRIR LES CLÉS UPLANET GÉOGRAPHIQUES (API à définir) ---
        // Exemple conceptuel (API à imaginer) :
        // const uplanetKeys = await discoverUPlanetKeys(currentGPS); // Fonction fictive et API à définir
        const uplanetKeys = ["npub1...", "npub2..."]; // Clés statiques pour l'exemple

        if (uplanetKeys && uplanetKeys.length > 0) {
            uplanetPostsDiv.innerHTML = ''; // Vider le message de chargement
            // --- ICI : CODE POUR RÉCUPÉRER LES ÉVÉNEMENTS (KIND 1) POUR CHAQUE CLÉ UPLANET (Utiliser librairie Nostr JS) ---
            // Exemple conceptuel (à remplacer par du vrai code Nostr) :
            // const uplanetPosts = await fetchPostsForKeys(relays, uplanetKeys); // Fonction fictive
            const examplePosts = [ // Posts statiques pour l'exemple
                { author: "@uplanet1", content: "Message UPlanet 1...", imageUrl: "img/placeholder-image.jpg", date: new Date() },
                { author: "@uplanet2", content: "Message UPlanet 2...", imageUrl: null, date: new Date() }
            ];
            displayUPlanetPosts(examplePosts);
        } else {
            uplanetPostsDiv.innerHTML = 'Aucun post UPlanet trouvé à proximité.';
        }
    }

    function displayUPlanetPosts(posts) {
        uplanetPostsDiv.innerHTML = ''; // Vider le message de chargement

        if (posts && posts.length > 0) {
            posts.forEach(postData => {
                const postElement = document.createElement('div');
                postElement.classList.add('post');

                const headerElement = document.createElement('div');
                headerElement.classList.add('post-header');
                headerElement.innerHTML = `
                    <img src="img/default-avatar.png" alt="Avatar" class="post-avatar">
                    <span class="post-author">${postData.author}</span>
                    <span class="post-date">${formatDate(postData.date)}</span>
                `;
                postElement.appendChild(headerElement);

                const contentElement = document.createElement('div');
                contentElement.classList.add('post-content');
                contentElement.innerHTML = `<p>${postData.content}</p>`;
                if (postData.imageUrl) {
                    contentElement.innerHTML += `<img src="${postData.imageUrl}" alt="Image jointe" class="post-image">`;
                }
                postElement.appendChild(contentElement);

                uplanetPostsDiv.appendChild(postElement);
            });
        } else {
            uplanetPostsDiv.innerHTML = 'Aucun post UPlanet à afficher.';
        }
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

    // Exemple d'utilisation de logRelayMessage (à intégrer dans la logique de connexion/communication Nostr)
    logRelayMessage("Démarrage de l'application...");
    logRelayMessage("Tentative de connexion aux relais par défaut...");


    // --- Initialisation ---
    fetchUPlanetPosts();
});
