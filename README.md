# Nostr Decentralized Trust System (NIP-101 Implementation)

This project implements a decentralized trust system for the Nostr protocol, as described in [NIP-101](https://github.com/papiche/nostr-nips/blob/NIP-101/101.md). It allows users to rate other users and content, calculate trust scores, and filter their feeds based on these trust ratings.

## Overview

This web-based application provides a user interface for interacting with the Nostr network and implementing a trust-based filtering system. It uses the following components:

*   **HTML (`index.html`):** Provides the structure of the application including a button to connect to nostr, a relay input, a feed section, a category selector, and a profile section.
*   **CSS (`style.css`):** Provides the basic styling of the elements.
*   **JavaScript (`script.js`):** Contains the core logic for connecting to Nostr, fetching events, calculating trust, and filtering content.

## Features

*   **Nostr Connection:** Connects to the Nostr network using the `window.nostr` interface provided by a Nostr extension like Alby or nos2x.
*   **Relay Selection:** Allows users to specify a Nostr relay URL, or will use the relays provided by the extension.
*   **User Profile Display:** Displays the user's profile information (name, picture, about) fetched from kind 0 events.
*   **Follow List:** Shows the list of public keys the user is following by fetching kind 3 events.
*   **Content Feed:** Fetches and displays notes from followed users and the current user by fetching kind 1 events.
*   **Trust Ratings (NIP-101):**
    *   Allows users to rate other users or specific content using a range of mood levels (e.g., ❤️,😊,👍,😐,😠,🤬).
    *   Sends trust ratings as kind 33 events, adhering to NIP-101.
    *   Displays trust scores for users based on direct and indirect ratings (using the `calculateTrustScores` function).
*    **Category Filtering:** Allow users to filter based on categories extracted from posts and kind 33 events.
*   **Feed Filtering:** Allows users to filter feed based on trust levels
*   **Infinite Scrolling:** Loads more messages as users scroll down the feed.
*   **Refresh Button:** Provides a way to reload all messages.
*  **Category selector**: Allows users to filter their feed by the most common categories.


## NIP-101 Implementation Details

This application implements the following aspects of NIP-101:

*   **Kind 33 Events:** Uses a new event kind (33) to represent trust ratings. The format of the event is as follows:
    ```json
    {
       "kind": 33,
       "content": "",
       "tags": [
          ["p", "public key of the user being rated"],
          ["rating", "numerical value between -100 and 100"],
          ["e", "id of triggering event (optional)"],
          ["category", "trust category (optional)"]
       ],
       "pubkey": "public key of the rater",
       "sig": "signature of the rater"
    }
    ```
*   **Trust Calculation:** Trust scores are calculated dynamically based on direct and indirect trust relationships using the `calculateTrustScores` function which uses the latest rating given by each rater. It computes the following scores: `allScore`,`friendsScore`,`categoryScore`, `friendCategoryScore`.
*   **Feed Filtering (Client-Side):** Feed filtering is implemented using the `updateTrustLevelDisplay` by reading kind 33 events, and a given category.

## How to Use

1.  **Install a Nostr Extension:** You will need a Nostr browser extension such as NOSTR Connect, Alby or nos2x.
2.  **Clone the Repository** in your web server directory. You need https access to the page for making wss connect possible (I am using ```ipfs add```)
3.  **Open `index.html`:** Open the `index.html` file in your web browser .
4.  **Connect to Nostr:** Click the "Connecter avec Nostr" button.
5.  **Specify Relay URL (Optional):** If needed, add your relay url, otherwise it will use the relays provided by your Nostr extension.
6.  **Rate Users and Content:** Use the mood buttons on each post to rate the content or the author.
7.  **View Trust Scores:** Trust scores are displayed next to each post.
8.  **Filter the feed:** You can filter the content based on categories using the dropdown.
9.  **Refresh the feed**: The refresh button will reload all posts, and reset the categories.

## Code Structure

*   **`script.js`**
    *   **Constants and variables**: At the top of the file, all required variables and constants are defined.
    *   **helper functions**: `hexToNpub`, `hexToNprofile1` and `bech32Checksum` are used to convert keys into a user friendly format.
    *   **UI helper functions**: `addPostToFeed`, `addCategorySelectorToUI`, `addFollowedKeyToUI`, `toggleTrustEvents`, `clearFeed`, `filterFeed`, and `updateCategories` are functions used to update the elements in the DOM.
    *   **Nostr functions**:
        *   `ratePost`: Used to send trust rating events as kind 33.
        *   `connectButton`: Function to connect to the Nostr extension and initialize the app.
         *   `fetchUserProfile`: Used to fetch the user profile information
          *   `fetchFollows`: Used to fetch the keys the user is following
           *  `fetchEvents`: Function to load messages of followed users.
        * `fetchAndDisplayTrustEvents` : Function to fetch and display trust events linked to a specific event ID
         *   `calculateTrustScores`: Used to compute the trust scores of an user.
         * `updateTrustLevelDisplay`: used to display trust scores in each post.
   *   **Scroll and Refresh logic**: `handleScroll` and `refreshFeed` are functions used to handle UI interactions.

## Security

*   Trust ratings are signed by their authors, ensuring authenticity.
*   The application does not store any private information.
*    Relay connections use wss connections to ensure data privacy.

## Known Issues and Limitations

*   This implementation provides a basic example of NIP-101. The trust calculation algorithm can be improved.
*   The UI is basic and could be enhanced.
*   The application currently handles only text notes.

**NB: Some functions are not working perfectly yet.** Please raise an issue or help with code...

## Contributing

If you would like to contribute to the project, please submit a pull request or open an issue with your suggestions.

## Disclaimer

This project is provided as-is and for educational and experimental purposes only. Please use it at your own discretion.

## References

*   [NIP-101: Decentralized Trust System for Nostr](https://github.com/papiche/nostr-nips/blob/NIP-101/101.md)
*   [Nostr protocol](https://github.com/nostr-protocol)
### - (^‿‿^) - 
/ipfs/QmSJn2EUWFq8ttkPpwnLKuoWhYYhWxtcvCPEC5yG87DA3L
