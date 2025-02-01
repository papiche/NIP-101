// Static data for the network
const user = { id: 'user', name: 'You', type: 'center' };
const n1Connections = [
    { id: 'n1_1', name: 'Alice', type: 'p2p', picture: 'https://placekitten.com/40/40', description: 'Tech enthusiast' },
    { id: 'n1_2', name: 'Bob', type: '12p', picture: 'https://placekitten.com/41/41', description: 'Art lover' },
    { id: 'n1_3', name: 'Charlie', type: 'p21', picture: 'https://placekitten.com/42/42', description: 'Social activist' },
    { id: 'n1_4', name: 'Dave', type: '12p', picture: 'https://placekitten.com/43/43', description: 'Gamer' },
  { id: 'n1_5', name: 'Eve', type: 'p2p', picture: 'https://placekitten.com/44/44', description: 'Music fan' },
    { id: 'n1_6', name: 'Frank', type: 'p21', picture: 'https://placekitten.com/45/45', description: 'Travel blogger' },
    { id: 'n1_7', name: 'Grace', type: 'p2p', picture: 'https://placekitten.com/46/46', description: 'Crypto trader' },
   { id: 'n1_8', name: 'Henry', type: '12p', picture: 'https://placekitten.com/47/47', description: 'Book reviewer' },
  { id: 'n1_9', name: 'Ivy', type: 'p21', picture: 'https://placekitten.com/48/48', description: 'Food critic' },
    { id: 'n1_10', name: 'Jack', type: '12p', picture: 'https://placekitten.com/49/49', description: 'Gardening guru' },
   { id: 'n1_11', name: 'Kate', type: 'p2p', picture: 'https://placekitten.com/50/50', description: 'Science geek' },
  { id: 'n1_12', name: 'Liam', type: 'p21', picture: 'https://placekitten.com/51/51', description: 'Film aficionado' }
];
const n2Connections = {
    'n1_1': [
        { id: 'n2_1_1', name: 'N2-Alice-1', trust: 0.8, category:'tech' },
        { id: 'n2_1_2', name: 'N2-Alice-2', trust: 0.5, category:'social' },
    ],
    'n1_2': [
        { id: 'n2_2_1', name: 'N2-Bob-1', trust: 0.7, category:'art' },
        { id: 'n2_2_2', name: 'N2-Bob-2', trust: 0.6, category:'social' }
    ],
    'n1_3': [
        { id: 'n2_3_1', name: 'N2-Charlie-1', trust: 0.9, category:'tech' },
        { id: 'n2_3_2', name: 'N2-Charlie-2', trust: 0.3, category:'social' }
    ],
     'n1_4': [
         { id: 'n2_4_1', name: 'N2-Dave-1', trust: 0.7, category:'art' },
         { id: 'n2_4_2', name: 'N2-Dave-2', trust: 0.9, category:'tech' }
     ],
      'n1_5': [
          { id: 'n2_5_1', name: 'N2-Eve-1', trust: 0.2, category:'social' },
          { id: 'n2_5_2', name: 'N2-Eve-2', trust: 0.8, category:'tech' }
      ],
  'n1_6': [
        { id: 'n2_6_1', name: 'N2-Frank-1', trust: 0.7, category:'art' },
        { id: 'n2_6_2', name: 'N2-Frank-2', trust: 0.4, category:'tech' }
    ],
     'n1_7': [
         { id: 'n2_7_1', name: 'N2-Grace-1', trust: 0.8, category:'tech' },
          { id: 'n2_7_2', name: 'N2-Grace-2', trust: 0.5, category:'social' },
      ],
   'n1_8': [
       { id: 'n2_8_1', name: 'N2-Henry-1', trust: 0.7, category:'art' },
         { id: 'n2_8_2', name: 'N2-Henry-2', trust: 0.6, category:'social' }
     ],
    'n1_9': [
        { id: 'n2_9_1', name: 'N2-Ivy-1', trust: 0.9, category:'tech' },
         { id: 'n2_9_2', name: 'N2-Ivy-2', trust: 0.3, category:'social' }
     ],
   'n1_10': [
       { id: 'n2_10_1', name: 'N2-Jack-1', trust: 0.7, category:'art' },
        { id: 'n2_10_2', name: 'N2-Jack-2', trust: 0.9, category:'tech' }
      ],
     'n1_11': [
          { id: 'n2_11_1', name: 'N2-Kate-1', trust: 0.2, category:'social' },
          { id: 'n2_11_2', name: 'N2-Kate-2', trust: 0.8, category:'tech' }
       ],
    'n1_12': [
        { id: 'n2_12_1', name: 'N2-Liam-1', trust: 0.7, category:'art' },
        { id: 'n2_12_2', name: 'N2-Liam-2', trust: 0.4, category:'tech' }
    ]
};

const cardContainer = document.getElementById('cardContainer');
const n2MainContainer = document.getElementById('n2Container');
let currentN2Container = null

function createCard(connection, container) {
    const card = document.createElement('div');
    card.classList.add('card');
    card.classList.add(connection.type)
    card.innerHTML = `
    <img src="${connection.picture}" alt="${connection.name} profile">
    <h3>${connection.name}</h3>
    <p>${connection.description}</p>`;
    card.addEventListener('click', () => showN2Connections(connection));
    container.appendChild(card);
     return card
}

function showN2Connections(connection) {
    // Clear previous N2 cards
    n2MainContainer.innerHTML = ''
     currentN2Container = document.createElement('div')
     currentN2Container.classList.add('n2-container');
    n2MainContainer.appendChild(currentN2Container)
    const n2ConnectionsForN1 = n2Connections[connection.id];
    if(n2ConnectionsForN1) {
        n2ConnectionsForN1.forEach(n2Connection => {
            const card = document.createElement('div');
            card.classList.add('card-n2');
            card.innerHTML = `<p>Name: ${n2Connection.name}</p>
            <p>  <span class="trust">Trust</span>: ${n2Connection.trust.toFixed(2)}</p>
             <p> <span class="category">Category</span>: ${n2Connection.category}</p>`;
            currentN2Container.appendChild(card);
        })
    }
}

// Generate N1 cards
n1Connections.forEach(connection => createCard(connection, cardContainer));
