// script.js

const API_BASE_URL = 'http://localhost:8000'; // URL de votre backend FastAPI (par défaut)

document.addEventListener('DOMContentLoaded', () => {
    setupAtomCanvas(); // Garder la fonction de dessin du canvas
    setupMoleculeAnalysis();
    setupInscriptionForm();
});

function setupMoleculeAnalysis() {
    const moleculeListUl = document.getElementById('moleculeList');
    const atomDetailsDiv = document.getElementById('atomDetails');

    if (!moleculeListUl || !atomDetailsDiv) return;

    // Simuler l'ID de l'utilisateur (à remplacer par une gestion d'authentification réelle)
    const userId = "user1@example.com"; // Pour la démo, on utilise un ID statique

    fetch(`${API_BASE_URL}/molecule_data/${userId}`) // Fetch depuis le backend
        .then(response => {
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            return response.json();
        })
        .then(molecules => {
            // Fonction pour afficher la liste des molécules (inchangée)
            function displayMoleculeList() {
                moleculeListUl.innerHTML = '';
                molecules.forEach(molecule => {
                    const li = document.createElement('li');
                    li.textContent = molecule.name;
                    li.addEventListener('click', () => displayMoleculeAtoms(molecule));
                    moleculeListUl.appendChild(li);
                });
            }

            // Fonction pour afficher les atomes dans une molécule (modifiée pour utiliser AtomData)
            function displayMoleculeAtoms(molecule) {
                atomDetailsDiv.innerHTML = `<h3>Molécule: ${molecule.name}</h3><ul>`;
                molecule.atoms.forEach(atom => { // 'atom' est maintenant un objet AtomData
                    atomDetailsDiv.innerHTML += `<li><strong>${atom.name}</strong> - Connexions: ${atom.connections}, Stabilité: ${atom.stability}, Valence: ${atom.valence}</li>`;
                });
                atomDetailsDiv.innerHTML += `</ul>`;
            }

            displayMoleculeList(); // Affichage initial de la liste des molécules
        })
        .catch(error => {
            console.error("Erreur lors de la récupération des données moléculaires:", error);
            atomDetailsDiv.innerHTML = `<p>Erreur lors du chargement des données moléculaires.</p>`;
        });
}


function setupAtomCanvas() {
    const canvas = document.getElementById('atomCanvas');
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const centerX = canvas.width / 2;
    const centerY = canvas.height / 2;
    const nucleusRadius = 20;
    const layerRadii = [50, 100, 150, 200, 250, 300, 350];

    // Simuler l'ID de l'utilisateur (à remplacer par une authentification réelle)
    const userId = "user1@example.com";

    function drawAtom(atomData) { // Prend AtomData en argument
        ctx.clearRect(0, 0, canvas.width, canvas.height);

        // Dessiner le noyau (Proton) - inchangé
        ctx.beginPath();
        ctx.arc(centerX, centerY, nucleusRadius, 0, Math.PI * 2);
        ctx.fillStyle = '#e74c3c';
        ctx.fill();
        ctx.closePath();

        // Dessiner les couches électroniques - modifié pour utiliser les données de AtomData
        if (atomData && atomData.layers && atomData.electrons_per_layer) {
            for (let i = 0; i < atomData.layers; i++) {
                drawElectronLayer(ctx, centerX, centerY, layerRadii[i], atomData.electrons_per_layer[i]);
            }
        }
    }

    function drawElectronLayer(ctx, centerX, centerY, radius, electronCount) {
        ctx.beginPath();
        ctx.arc(centerX, centerY, radius, 0, Math.PI * 2);
        ctx.strokeStyle = 'rgba(0, 0, 0, 0.2)';
        ctx.stroke();
        ctx.closePath();

        for (let i = 0; i < electronCount; i++) {
            const angle = (Math.PI * 2 / electronCount) * i;
            const electronX = centerX + radius * Math.cos(angle);
            const electronY = centerY + radius * Math.sin(angle);

            ctx.beginPath();
            ctx.arc(electronX, electronY, 5, 0, Math.PI * 2);
            ctx.fillStyle = '#3498db';
            ctx.fill();
            ctx.closePath();
        }
    }


    // Fetch des données atomiques depuis le backend
    fetch(`${API_BASE_URL}/atom_data/${userId}`)
        .then(response => {
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            return response.json();
        })
        .then(atomData => {
            drawAtom(atomData); // Dessiner l'atome en utilisant les données fetchées
        })
        .catch(error => {
            console.error("Erreur lors de la récupération des données atomiques:", error);
            // Gérer l'erreur d'affichage de l'atome (ex: afficher un atome par défaut ou un message d'erreur)
        });
}


function setupInscriptionForm() {
    const form = document.getElementById('inscriptionForm');
    if (!form) return;

    form.addEventListener('submit', function(event) {
        event.preventDefault();
        const emailInput = document.getElementById('email');
        const email = emailInput.value;

        if (email && isValidEmail(email)) {
            fetch(`${API_BASE_URL}/register/`, { // Envoi POST au backend
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({ email: email })
            })
            .then(response => {
                if (response.ok) {
                    return response.json();
                } else {
                    return response.json().then(err => { throw new Error(err.detail || `Erreur d'inscription: ${response.status}`); }); // Gestion des erreurs FastAPI
                }
            })
            .then(data => {
                alert(data.message || `Merci de vous être inscrit avec l'email: ${email} !\nRestez à l'écoute pour les prochaines nouvelles d'Atomic Nostr.`);
                emailInput.value = '';
            })
            .catch(error => {
                alert(`Erreur d'inscription: ${error.message}`);
                console.error("Erreur lors de l'inscription:", error);
            });
        } else {
            alert('Veuillez entrer une adresse email valide.');
        }
    });
}


function isValidEmail(email) {
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return emailRegex.test(email);
}
