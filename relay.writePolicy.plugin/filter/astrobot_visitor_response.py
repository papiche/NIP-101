#!/usr/bin/env python3
"""
AstroBot Visitor Response Generator
Utilise les personas d'AstroBot pour générer des réponses personnalisées aux visiteurs
basées sur leur profil NOSTR et leur message.
"""

import os
import json
import sys
import subprocess
import requests
import re
import logging
import time
from datetime import datetime
from typing import Dict, List, Optional, Tuple

class AstroBotVisitorResponder:
    def __init__(self):
        self.base_path = os.path.expanduser("~/.zen")
        self.astrobot_path = os.path.join(self.base_path, "workspace", "OC2UPlanet", "AstroBot")
        self.workspace_path = os.path.join(self.astrobot_path, "workspace")
        self.banks_config_file = os.path.join(self.workspace_path, "memory_banks_config.json")
        
        # Configuration du logging
        self._setup_logging()
        
        # Relais NOSTR publics pour récupérer les profils
        self.nostr_relays = [
            "wss://relay.damus.io",
            "wss://nos.lol",
            "wss://relay.snort.social",
            "wss://relay.nostr.band"
        ]
        
        # Charger la configuration des personas
        self.banks_config = self._load_banks_config()
        self.logger.info("AstroBotVisitorResponder initialized")
    
    def _setup_logging(self):
        """Configure le système de logging"""
        # Créer le répertoire tmp s'il n'existe pas
        tmp_dir = os.path.join(self.base_path, "tmp")
        os.makedirs(tmp_dir, exist_ok=True)
        
        # Configuration du logger
        log_file = os.path.join(tmp_dir, "IA.log")
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(log_file, encoding='utf-8')
            ]
        )
        self.logger = logging.getLogger('AstroBotVisitorResponder')
        
    def _extract_image_urls(self, content: str) -> List[str]:
        """
        Extract image URLs from message content.
        
        Args:
            content (str): The message content to analyze
            
        Returns:
            List[str]: List of image URLs found in the content
        """
        # Regex pattern to match image URLs
        image_pattern = r'https?://[^\s]+\.(jpg|jpeg|png|gif|webp|bmp|tiff|svg)(?:\?[^\s]*)?'
        matches = re.findall(image_pattern, content, re.IGNORECASE)
        
        # Reconstruct full URLs
        image_urls = []
        for match in matches:
            # Find the full URL that contains this extension
            url_pattern = r'https?://[^\s]*\.' + re.escape(match) + r'(?:\?[^\s]*)?'
            url_matches = re.findall(url_pattern, content, re.IGNORECASE)
            image_urls.extend(url_matches)
        
        # Remove duplicates while preserving order
        seen = set()
        unique_urls = []
        for url in image_urls:
            if url not in seen:
                seen.add(url)
                unique_urls.append(url)
        
        self.logger.info(f"Found {len(unique_urls)} image URLs: {unique_urls}")
        return unique_urls
    
    def _analyze_image_with_ai(self, image_url: str) -> Optional[str]:
        """
        Analyze an image using describe_image.py script.
        
        Args:
            image_url (str): URL of the image to analyze
            
        Returns:
            Optional[str]: Description of the image, or None if analysis fails
        """
        self.logger.info(f"Analyzing image: {image_url}")
        
        # Vérification rapide de l'URL avant analyse
        if not image_url or not image_url.startswith(('http://', 'https://')):
            self.logger.warning(f"Invalid image URL: {image_url}")
            return None
        
        try:
            # Get the path to describe_image.py
            describe_script = os.path.join(self.base_path, "Astroport.ONE", "IA", "describe_image.py")
            
            if not os.path.exists(describe_script):
                self.logger.error(f"describe_image.py not found at {describe_script}")
                return None
            
            # Call describe_image.py with the image URL (timeout réduit pour éviter le spam)
            cmd = ['python3', describe_script, image_url, '--json']
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
            
            if result.returncode == 0 and result.stdout.strip():
                try:
                    response = json.loads(result.stdout)
                    description = response.get('description', '')
                    self.logger.info(f"Image analysis successful: {description[:100]}...")
                    return description
                except json.JSONDecodeError as e:
                    self.logger.error(f"Failed to parse image analysis JSON: {e}")
                    return None
            else:
                self.logger.warning(f"Image analysis failed: {result.stderr}")
                return None
                
        except subprocess.TimeoutExpired:
            self.logger.error("Image analysis timed out (30s)")
            return None
        except Exception as e:
            self.logger.error(f"Error analyzing image: {e}")
            return None

    def _extract_json_from_markdown(self, text: str) -> str:
        """
        Extract JSON from markdown code blocks if present.
        Handles cases where AI returns JSON wrapped in ```json ... ``` or ``` ... ```
        
        Args:
            text (str): The text that may contain JSON in markdown code blocks
            
        Returns:
            str: The extracted JSON string, or the original text if no code block found
        """
        # Try to extract JSON from markdown code blocks
        # Pattern 1: ```json ... ```
        json_pattern = r'```json\s*\n?(.*?)\n?```'
        match = re.search(json_pattern, text, re.DOTALL)
        if match:
            return match.group(1).strip()
        
        # Pattern 2: ``` ... ```
        code_pattern = r'```\s*\n?(.*?)\n?```'
        match = re.search(code_pattern, text, re.DOTALL)
        if match:
            return match.group(1).strip()
        
        # No markdown code block found, return as is
        return text.strip()
    
    def _load_banks_config(self) -> Dict:
        """Charge la configuration des personas d'AstroBot"""
        if os.path.exists(self.banks_config_file):
            try:
                with open(self.banks_config_file, 'r', encoding='utf-8') as f:
                    config = json.load(f)
                    self.logger.info(f"Configuration loaded from {self.banks_config_file}")
                    return config
            except Exception as e:
                self.logger.error(f"Error loading config from {self.banks_config_file}: {e}")
        
        # Configuration par défaut si le fichier n'existe pas
        self.logger.info("Using default configuration")
        return {
            "banks": {
                "0": {
                    "name": "Ingénieur/Technicien",
                    "description": "Voix experte et pragmatique qui s'adresse à des pairs.",
                    "themes": ["technologie", "developpeur", "crypto", "logiciel-libre", "g1", "innovation", "digital", "monnaie"],
                    "corpus": {
                        "vocabulary": ["protocole", "infrastructure", "décentralisation", "blockchain", "open-source"],
                        "tone": "pragmatique, précis, direct, informatif"
                    }
                },
                "1": {
                    "name": "Philosophe/Militant",
                    "description": "Voix visionnaire et engagée qui s'adresse aux citoyens acteurs du changement.",
                    "themes": ["souverainete", "transition", "ecologie", "collectif", "local", "partage", "entraide", "liberte"],
                    "corpus": {
                        "vocabulary": ["souveraineté populaire", "biens communs", "résilience", "alternative aux GAFAM"],
                        "tone": "inspirant, visionnaire, éthique"
                    }
                },
                "2": {
                    "name": "Créateur/Artisan",
                    "description": "Voix concrète et valorisante qui s'adresse aux artisans et créateurs.",
                    "themes": ["creatif", "savoir-faire", "artisanat", "creation", "artiste", "musique", "produits-naturels"],
                    "corpus": {
                        "vocabulary": ["création de valeur", "autonomie", "circuit-court", "juste rémunération"],
                        "tone": "concret, valorisant, pragmatique, passionné"
                    }
                },
                "3": {
                    "name": "Holistique/Thérapeute",
                    "description": "Voix bienveillante et inspirante qui s'adresse à la communauté du bien-être.",
                    "themes": ["spiritualite", "nature", "permaculture", "bien-etre", "therapeute", "holistique"],
                    "corpus": {
                        "vocabulary": ["harmonie", "équilibre", "bien-être", "conscience", "croissance"],
                        "tone": "inspirant, doux, bienveillant"
                    }
                }
            }
        }
    
    def _query_ia(self, prompt: str, expect_json: bool = False, target_language: str = 'fr') -> Optional[str]:
        """Appelle l'IA en utilisant la même méthode que les agents AstroBot avec gestion de langue"""
        question_script = os.path.join(self.base_path, "Astroport.ONE", "IA", "question.py")
        
        if not os.path.exists(question_script):
            self.logger.error(f"question.py script not found at {question_script}")
            return None
        
        # Ajouter l'instruction de langue au prompt
        prompt_with_language = self._add_language_instruction(prompt, target_language)
        
        command = ['python3', question_script, prompt_with_language]
        if expect_json:
            command.append('--json')
        
        self.logger.debug(f"Exécution de la commande IA : {' '.join(command[:2])}...")
        self.logger.info("📞 Interrogation de l'IA en cours... Le traitement du prompt peut être long.")
        self.logger.debug(f"Taille du prompt: {len(prompt_with_language)} caractères.")
        self.logger.debug(f"🌍 Langue cible : {target_language}")
        start_time = time.time()

        try:
            result = subprocess.run(command, capture_output=True, text=True, check=True, timeout=60)
            
            end_time = time.time()
            self.logger.info(f"✅ Réponse de l'IA reçue en {end_time - start_time:.2f} secondes.")
            self.logger.debug(f"Réponse brute de l'IA reçue : {result.stdout.strip()}")

            if expect_json:
                return json.loads(result.stdout)
            return result.stdout.strip()

        except subprocess.CalledProcessError as e:
            self.logger.error(f"❌ Le script d'IA a retourné une erreur.")
            self.logger.error(f"   Code de retour : {e.returncode}")
            self.logger.error(f"   Sortie standard (stdout) : {e.stdout.strip()}")
            self.logger.error(f"   Sortie d'erreur (stderr) : {e.stderr.strip()}")
            return None
        except subprocess.TimeoutExpired:
            self.logger.error("❌ Timeout lors de l'appel à l'IA (60 secondes)")
            return None
        except Exception as e:
            self.logger.error(f"❌ Erreur inattendue lors de l'appel à l'IA: {e}")
            return None
    
    def _add_language_instruction(self, prompt: str, target_language: str) -> str:
        """Ajoute l'instruction de langue au prompt si nécessaire"""
        # Vérifier si le prompt contient déjà des instructions de langue
        language_indicators = {
            'en': ['english', 'in english', 'write in english', 'you are uplanet'],
            'fr': ['français', 'en français', 'écris en français', 'tu es l\'agent stratège'],
            'es': ['español', 'en español', 'escribe en español'],
            'de': ['deutsch', 'auf deutsch', 'schreibe auf deutsch'],
            'it': ['italiano', 'in italiano', 'scrivi in italiano'],
            'pt': ['português', 'em português', 'escreva em português']
        }
        
        prompt_lower = prompt.lower()
        prompt_is_in_target_language = False
        
        # Vérifier si le prompt contient déjà des indicateurs de langue cible
        if target_language in language_indicators:
            for indicator in language_indicators[target_language]:
                if indicator in prompt_lower:
                    prompt_is_in_target_language = True
                    break
        
        # Ajouter l'instruction de langue seulement si nécessaire
        if not prompt_is_in_target_language:
            language_instructions = {
                'fr': "\n\nIMPORTANT : Écris le message en français.",
                'en': "\n\nIMPORTANT : Write the message in English.",
                'es': "\n\nIMPORTANT : Escribe el mensaje en español.",
                'de': "\n\nIMPORTANT : Schreibe die Nachricht auf Deutsch.",
                'it': "\n\nIMPORTANT : Scrivi il messaggio in italiano.",
                'pt': "\n\nIMPORTANT : Escreva a mensagem em português."
            }
            
            language_instruction = language_instructions.get(target_language, f"\n\nIMPORTANT : Écris le message en {target_language.upper()}.")
            return prompt + language_instruction
        else:
            return prompt
    
    def detect_language(self, text: str) -> str:
        """Détecte la langue du texte en utilisant des mots-clés simples"""
        self.logger.info("Detecting language from text")
        
        # Mots-clés pour détecter les langues
        language_keywords = {
            'en': ['the', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for', 'of', 'with', 'by', 'is', 'are', 'was', 'were', 'have', 'has', 'had', 'will', 'would', 'could', 'should', 'hello', 'hi', 'hey', 'good', 'bad', 'yes', 'no', 'please', 'thank', 'thanks'],
            'fr': ['le', 'la', 'les', 'un', 'une', 'des', 'et', 'ou', 'mais', 'dans', 'sur', 'avec', 'sans', 'pour', 'par', 'de', 'du', 'des', 'est', 'sont', 'était', 'étaient', 'avoir', 'a', 'ont', 'eu', 'bonjour', 'salut', 'oui', 'non', 'merci', 's\'il', 'vous', 'nous'],
            'es': ['el', 'la', 'los', 'las', 'un', 'una', 'unos', 'unas', 'y', 'o', 'pero', 'en', 'con', 'sin', 'por', 'para', 'de', 'del', 'es', 'son', 'era', 'eran', 'tener', 'tiene', 'tienen', 'hola', 'sí', 'no', 'gracias', 'por', 'favor'],
            'de': ['der', 'die', 'das', 'den', 'dem', 'des', 'ein', 'eine', 'eines', 'und', 'oder', 'aber', 'in', 'auf', 'mit', 'ohne', 'für', 'von', 'ist', 'sind', 'war', 'waren', 'haben', 'hat', 'haben', 'hallo', 'ja', 'nein', 'danke', 'bitte'],
            'it': ['il', 'la', 'lo', 'gli', 'le', 'un', 'una', 'uno', 'e', 'o', 'ma', 'in', 'su', 'con', 'senza', 'per', 'di', 'dal', 'è', 'sono', 'era', 'erano', 'avere', 'ha', 'hanno', 'ciao', 'sì', 'no', 'grazie', 'per', 'favore'],
            'pt': ['o', 'a', 'os', 'as', 'um', 'uma', 'uns', 'umas', 'e', 'ou', 'mas', 'em', 'com', 'sem', 'para', 'por', 'de', 'do', 'da', 'é', 'são', 'era', 'eram', 'ter', 'tem', 'têm', 'olá', 'oi', 'sim', 'não', 'obrigado', 'por', 'favor']
        }
        
        text_lower = text.lower()
        word_count = len(text_lower.split())
        
        if word_count < 3:
            # Texte trop court, utiliser le français par défaut
            return 'fr'
        
        language_scores = {}
        
        for lang, keywords in language_keywords.items():
            score = 0
            for keyword in keywords:
                if keyword in text_lower:
                    score += 1
            language_scores[lang] = score
        
        # Trouver la langue avec le meilleur score
        if language_scores:
            best_language = max(language_scores.keys(), key=lambda x: language_scores[x])
            best_score = language_scores[best_language]
            
            # Seuil minimum pour considérer la détection comme fiable
            if best_score >= 2:
                self.logger.info(f"Language detected: {best_language} (score: {best_score})")
                return best_language
        
        # Si aucune langue n'est détectée de manière fiable, utiliser le français
        self.logger.info("No language detected reliably, using French as default")
        return 'fr'
    
    def get_nostr_profile(self, pubkey: str) -> Optional[Dict]:
        """Récupère le profil NOSTR d'un utilisateur depuis les relais publics"""
        self.logger.info(f"Fetching NOSTR profile for pubkey: {pubkey[:10]}...")
        try:
            profile_data = {}
            
            # Essayer d'utiliser nostr-tools si disponible
            try:
                cmd = f"nostr-tools profile {pubkey}"
                result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=10)
                if result.returncode == 0:
                    profile_data = json.loads(result.stdout)
                    self.logger.info("Profile retrieved using nostr-tools")
                    return profile_data
            except Exception as e:
                self.logger.debug(f"nostr-tools failed: {e}")
            
            # Fallback: essayer avec curl et une API NOSTR
            try:
                api_url = f"https://api.nostr.band/v0/profile/{pubkey}"
                response = requests.get(api_url, timeout=10)
                if response.status_code == 200:
                    data = response.json()
                    if 'profile' in data:
                        self.logger.info("Profile retrieved using nostr.band API")
                        return data['profile']
            except Exception as e:
                self.logger.debug(f"nostr.band API failed: {e}")
            
            # Fallback: essayer avec une autre API
            try:
                api_url = f"https://api.snort.social/v1/profile/{pubkey}"
                response = requests.get(api_url, timeout=10)
                if response.status_code == 200:
                    self.logger.info("Profile retrieved using snort.social API")
                    return response.json()
            except Exception as e:
                self.logger.debug(f"snort.social API failed: {e}")
            
            self.logger.warning("No profile data retrieved from any source")
            return profile_data
        except Exception as e:
            self.logger.error(f"Error retrieving profile: {e}")
            return None
    
    def get_user_favorite_relays(self, pubkey: str) -> List[str]:
        """Récupère les relais favoris d'un utilisateur depuis les plateformes publiques"""
        self.logger.info(f"Fetching favorite relays for pubkey: {pubkey[:10]}...")
        relays = []
        
        try:
            # Essayer d'abord avec nostr-tools pour récupérer les relais
            try:
                cmd = f"nostr-tools query --authors {pubkey} --kinds 3 --limit 1"
                result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=10)
                if result.returncode == 0 and result.stdout.strip():
                    for line in result.stdout.strip().split('\n'):
                        if line.strip():
                            try:
                                contact_data = json.loads(line)
                                if contact_data.get('kind') == 3:  # Contact list
                                    tags = contact_data.get('tags', [])
                                    for tag in tags:
                                        if len(tag) >= 2 and tag[0] == 'r':  # Relay tag
                                            relay_url = tag[1]
                                            if relay_url.startswith('wss://') or relay_url.startswith('ws://'):
                                                relays.append(relay_url)
                            except json.JSONDecodeError:
                                continue
                    
                    if relays:
                        self.logger.info(f"Found {len(relays)} favorite relays using nostr-tools")
                        return self._optimize_relay_selection(relays)
            except Exception as e:
                self.logger.debug(f"nostr-tools relay query failed: {e}")
            
            # Fallback: essayer avec les APIs publiques pour récupérer les relais
            try:
                # API nostr.band pour les relais
                api_url = f"https://api.nostr.band/v0/relays/{pubkey}"
                response = requests.get(api_url, timeout=10)
                if response.status_code == 200:
                    data = response.json()
                    if 'relays' in data:
                        for relay_info in data['relays']:
                            relay_url = relay_info.get('url', '')
                            if relay_url.startswith('wss://') or relay_url.startswith('ws://'):
                                relays.append(relay_url)
                        
                        if relays:
                            self.logger.info(f"Found {len(relays)} favorite relays using nostr.band API")
                            return self._optimize_relay_selection(relays)
            except Exception as e:
                self.logger.debug(f"nostr.band relays API failed: {e}")
            
            # Si aucun relais spécifique trouvé, utiliser les relais par défaut
            self.logger.info("No specific relays found, using default public relays")
            return self._optimize_relay_selection(self.nostr_relays)
            
        except Exception as e:
            self.logger.error(f"Error retrieving user relays: {e}")
            return self._optimize_relay_selection(self.nostr_relays)  # Fallback sur les relais par défaut
    
    def get_recent_messages(self, pubkey: str, limit: int = 10) -> List[Dict]:
        """Récupère les derniers messages d'un utilisateur depuis ses relais favoris"""
        self.logger.info(f"Fetching {limit} recent messages for pubkey: {pubkey[:10]}...")
        
        # Récupérer d'abord les relais favoris de l'utilisateur
        user_relays = self.get_user_favorite_relays(pubkey)
        self.logger.info(f"Using {len(user_relays)} user-specific relays: {user_relays}")
        
        # Timeout global pour éviter que la récupération prenne trop de temps
        start_time = time.time()
        max_total_time = 30  # 30 secondes maximum pour toute la récupération
        
        try:
            # Vérifier le timeout global
            if time.time() - start_time > max_total_time:
                self.logger.warning("Global timeout reached, stopping message retrieval")
                return []
            
            # Essayer d'abord avec nostr-tools sur les relais spécifiques de l'utilisateur
            try:
                # Construire la commande avec les relais spécifiques
                relay_args = " ".join([f"--relay {relay}" for relay in user_relays])
                cmd = f"nostr-tools query {relay_args} --authors {pubkey} --kinds 1 --limit {limit}"
                result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=15)
                if result.returncode == 0 and result.stdout.strip():
                    messages = []
                    for line in result.stdout.strip().split('\n'):
                        if line.strip():
                            try:
                                message_data = json.loads(line)
                                if message_data.get('kind') == 1:
                                    messages.append({
                                        'content': message_data.get('content', ''),
                                        'created_at': message_data.get('created_at', 0),
                                        'id': message_data.get('id', '')
                                    })
                            except json.JSONDecodeError:
                                continue
                    
                    if messages:
                        self.logger.info(f"Retrieved {len(messages)} recent messages using nostr-tools on user relays")
                        return messages
            except Exception as e:
                self.logger.debug(f"nostr-tools query on user relays failed: {e}")
            
            # Vérifier le timeout global avant de continuer
            if time.time() - start_time > max_total_time:
                self.logger.warning("Global timeout reached, stopping message retrieval")
                return []
            
            # Fallback: utiliser les APIs publiques
            try:
                # Essayer avec l'API nostr.band
                api_url = f"https://api.nostr.band/v0/notes/{pubkey}?limit={limit}"
                response = requests.get(api_url, timeout=10)
                if response.status_code == 200:
                    data = response.json()
                    if 'notes' in data and data['notes']:
                        messages = []
                        for note in data['notes'][:limit]:
                            messages.append({
                                'content': note.get('content', ''),
                                'created_at': note.get('created_at', 0),
                                'id': note.get('id', '')
                            })
                        self.logger.info(f"Retrieved {len(messages)} recent messages using nostr.band API")
                        return messages
            except Exception as e:
                self.logger.debug(f"nostr.band API failed: {e}")
            
            # Vérifier le timeout global avant de continuer
            if time.time() - start_time > max_total_time:
                self.logger.warning("Global timeout reached, stopping message retrieval")
                return []
            
            # Fallback: essayer avec snort.social API
            try:
                api_url = f"https://api.snort.social/v1/notes/{pubkey}?limit={limit}"
                response = requests.get(api_url, timeout=10)
                if response.status_code == 200:
                    data = response.json()
                    if isinstance(data, list):
                        messages = []
                        for note in data[:limit]:
                            messages.append({
                                'content': note.get('content', ''),
                                'created_at': note.get('created_at', 0),
                                'id': note.get('id', '')
                            })
                        self.logger.info(f"Retrieved {len(messages)} recent messages using snort.social API")
                        return messages
            except Exception as e:
                self.logger.debug(f"snort.social API failed: {e}")
            
            # Vérifier le timeout global avant de continuer
            if time.time() - start_time > max_total_time:
                self.logger.warning("Global timeout reached, stopping message retrieval")
                return []
            
            # Fallback: essayer avec l'API de damus.io
            try:
                api_url = f"https://api.damus.io/v1/notes/{pubkey}?limit={limit}"
                response = requests.get(api_url, timeout=10)
                if response.status_code == 200:
                    data = response.json()
                    if isinstance(data, list):
                        messages = []
                        for note in data[:limit]:
                            messages.append({
                                'content': note.get('content', ''),
                                'created_at': note.get('created_at', 0),
                                'id': note.get('id', '')
                            })
                        self.logger.info(f"Retrieved {len(messages)} recent messages using damus.io API")
                        return messages
            except Exception as e:
                self.logger.debug(f"damus.io API failed: {e}")
            
            # Vérifier le timeout global avant le dernier fallback
            if time.time() - start_time > max_total_time:
                self.logger.warning("Global timeout reached, stopping message retrieval")
                return []
            
            # Dernier fallback: essayer avec les relais NOSTR directement
            try:
                messages = self._query_nostr_relays_directly(pubkey, limit, user_relays)
                if messages:
                    self.logger.info(f"Retrieved {len(messages)} recent messages using direct relay queries")
                    return messages
            except Exception as e:
                self.logger.debug(f"Direct relay queries failed: {e}")
            
            # Si aucune méthode n'a fonctionné
            self.logger.warning("No recent messages found from any public source")
            return []
                
        except Exception as e:
            self.logger.error(f"Error retrieving recent messages: {e}")
            return []
    
    def _query_nostr_relays_directly(self, pubkey: str, limit: int, user_relays: List[str] = None) -> List[Dict]:
        """Interroge directement les relais NOSTR via WebSocket"""
        self.logger.info("Trying direct relay queries as last resort")
        messages = []
        
        # Utiliser les relais spécifiques de l'utilisateur ou les relais par défaut
        relays_to_query = user_relays if user_relays else self.nostr_relays
        relays_to_query = relays_to_query[:3]  # Limiter à 3 relais pour éviter les timeouts
        
        for relay in relays_to_query:
            try:
                cmd = f"nostr-tools query --relay {relay} --authors {pubkey} --kinds 1 --limit {limit}"
                result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=10)
                if result.returncode == 0 and result.stdout.strip():
                    for line in result.stdout.strip().split('\n'):
                        if line.strip():
                            try:
                                message_data = json.loads(line)
                                if message_data.get('kind') == 1:
                                    messages.append({
                                        'content': message_data.get('content', ''),
                                        'created_at': message_data.get('created_at', 0),
                                        'id': message_data.get('id', '')
                                    })
                            except json.JSONDecodeError:
                                continue
                    
                    if messages:
                        self.logger.info(f"Found {len(messages)} messages from user relay {relay}")
                        break
            except Exception as e:
                self.logger.debug(f"User relay {relay} failed: {e}")
                continue
        
        return messages[:limit]  # Limiter le nombre de messages retournés
    
    def _optimize_relay_selection(self, relays: List[str]) -> List[str]:
        """Optimise la sélection des relais en privilégiant les plus fiables et rapides"""
        self.logger.info("Optimizing relay selection for better performance")
        
        # Relais connus pour être fiables et rapides
        preferred_relays = [
            "wss://relay.damus.io",
            "wss://nos.lol", 
            "wss://relay.snort.social",
            "wss://relay.nostr.band",
            "wss://relay.damus.io",
            "wss://relay.nostr.info"
        ]
        
        # Mélanger les relais de l'utilisateur avec les relais préférés
        optimized_relays = []
        
        # D'abord, ajouter les relais préférés qui sont aussi dans la liste de l'utilisateur
        for preferred in preferred_relays:
            if preferred in relays and preferred not in optimized_relays:
                optimized_relays.append(preferred)
        
        # Ensuite, ajouter les autres relais de l'utilisateur
        for relay in relays:
            if relay not in optimized_relays:
                optimized_relays.append(relay)
        
        # Enfin, ajouter des relais préférés qui ne sont pas dans la liste de l'utilisateur
        for preferred in preferred_relays:
            if preferred not in optimized_relays and len(optimized_relays) < 5:
                optimized_relays.append(preferred)
        
        self.logger.info(f"Optimized relay selection: {optimized_relays[:5]}")
        return optimized_relays[:5]  # Limiter à 5 relais maximum
    
    def extract_themes_from_profile_and_messages(self, profile: Dict, messages: List[Dict], current_message: str) -> List[str]:
        """Extrait les thèmes pertinents du profil, des messages récents et du message actuel"""
        self.logger.info("Extracting themes from profile, recent messages and current message")
        themes = set()
        
        # Mapping exact des thèmes vers les thèmes des personas
        # Bank 0: technologie, developpeur, crypto, logiciel-libre, g1, innovation, digital, monnaie
        # Bank 1: souverainete, transition, ecologie, collectif, local, partage, entraide, liberte
        # Bank 2: creatif, savoir-faire, artisanat, creation, artiste, musique, produits-naturels
        # Bank 3: spiritualite, nature, permaculture, bien-etre, therapeute, holistique
        
        # Extraire les thèmes du profil
        if profile:
            # Analyser le nom d'affichage avec détection spécifique
            display_name = profile.get('display_name', '').lower()
            
            # Détection technologie/developpeur
            if any(kw in display_name for kw in ['dev', 'tech', 'crypto', 'engineer', 'developer', 'coder', 'programmer']):
                themes.update(['technologie', 'developpeur', 'digital'])
            
            # Détection créatif/artiste
            if any(kw in display_name for kw in ['art', 'music', 'artist', 'musician', 'creator', 'maker', 'designer']):
                themes.update(['creatif', 'artiste', 'creation'])
            
            # Détection nature/spiritualité
            if any(kw in display_name for kw in ['nature', 'zen', 'yoga', 'meditat', 'healing', 'therapist']):
                themes.update(['nature', 'spiritualite', 'bien-etre'])
            
            # Détection souveraineté/liberté
            if any(kw in display_name for kw in ['freedom', 'libre', 'sovereign', 'anarchist', 'activist']):
                themes.update(['souverainete', 'liberte'])
            
            # Analyser la bio avec mapping vers les thèmes des personas
            bio = profile.get('about', '').lower()
            
            profile_theme_keywords = {
                'technologie': ['tech', 'programming', 'software', 'computer', 'code', 'developer', 'engineer', 'dev', 'coder', 'it', 'digital', 'web', 'app'],
                'developpeur': ['developer', 'programmer', 'coder', 'coding', 'programming', 'software engineer', 'full stack', 'backend', 'frontend'],
                'crypto': ['crypto', 'bitcoin', 'blockchain', 'ethereum', 'nostr', 'web3', 'defi', 'nft', 'satoshi'],
                'logiciel-libre': ['open source', 'free software', 'gnu', 'linux', 'foss', 'libre', 'opensource', 'open-source'],
                'innovation': ['innovation', 'innovative', 'future', 'pioneering', 'cutting edge', 'disruptive'],
                'monnaie': ['currency', 'money', 'monnaie', 'économie', 'economy', 'finance', 'ğ1', 'g1', 'june'],
                'souverainete': ['sovereign', 'sovereignty', 'souveraineté', 'autonomy', 'independence', 'self-sufficient', 'autonomous'],
                'transition': ['transition', 'change', 'transformation', 'evolve', 'shift'],
                'ecologie': ['ecology', 'ecological', 'ecologie', 'sustainable', 'sustainability', 'climate', 'environment'],
                'collectif': ['collective', 'community', 'collaboration', 'together', 'ensemble', 'collectif', 'cooperative'],
                'local': ['local', 'locality', 'neighborhood', 'regional', 'territoire'],
                'partage': ['share', 'sharing', 'partage', 'commons', 'communs', 'mutual aid'],
                'liberte': ['freedom', 'liberty', 'free', 'libre', 'liberté', 'liberation'],
                'creatif': ['creative', 'creativity', 'création', 'art', 'artistic', 'design', 'craft'],
                'artiste': ['artist', 'artiste', 'musician', 'painter', 'sculptor', 'photographer', 'writer'],
                'musique': ['music', 'musique', 'musician', 'song', 'compose', 'audio', 'sound'],
                'artisanat': ['craft', 'artisan', 'handmade', 'handcraft', 'artisanat', 'maker'],
                'savoir-faire': ['skill', 'craftsmanship', 'expertise', 'know-how', 'savoir-faire', 'technique'],
                'spiritualite': ['spiritual', 'spirituality', 'spiritualité', 'consciousness', 'awakening', 'enlightenment'],
                'nature': ['nature', 'natural', 'earth', 'planet', 'wild', 'wilderness', 'outdoor'],
                'permaculture': ['permaculture', 'agroecology', 'regenerative', 'organic farming'],
                'bien-etre': ['wellness', 'wellbeing', 'bien-être', 'health', 'healthy', 'santé'],
                'therapeute': ['therapist', 'therapy', 'healing', 'healer', 'thérapeute', 'therapeutic']
            }
            
            for theme, keywords in profile_theme_keywords.items():
                if any(keyword in bio for keyword in keywords):
                    themes.add(theme)
        
        # Analyser les messages récents et le message actuel
        all_messages_text = current_message.lower()
        for message in messages:
            all_messages_text += " " + message.get('content', '').lower()
        
        # Keywords pour messages avec mapping vers thèmes personas
        message_theme_keywords = {
            'technologie': ['tech', 'technology', 'software', 'computer', 'digital', 'app', 'application', 'code'],
            'developpeur': ['dev', 'developer', 'programming', 'coding', 'code', 'script', 'api'],
            'crypto': ['crypto', 'bitcoin', 'blockchain', 'nostr', 'ethereum', 'btc', 'web3', 'decentralized'],
            'innovation': ['innovation', 'innovative', 'new', 'future', 'modern'],
            'digital': ['digital', 'numérique', 'online', 'internet', 'web'],
            'souverainete': ['sovereign', 'sovereignty', 'autonomy', 'independence', 'self-sufficient'],
            'liberte': ['freedom', 'liberty', 'free', 'libre', 'liberation'],
            'ecologie': ['ecology', 'ecological', 'sustainable', 'environment', 'climate', 'green'],
            'collectif': ['community', 'collective', 'together', 'collaboration', 'group'],
            'partage': ['share', 'sharing', 'commons', 'mutual'],
            'creatif': ['creative', 'creativity', 'art', 'artistic', 'create'],
            'artiste': ['artist', 'music', 'musician', 'paint', 'draw', 'compose'],
            'musique': ['music', 'song', 'audio', 'sound', 'melody'],
            'artisanat': ['craft', 'handmade', 'artisan', 'maker'],
            'spiritualite': ['spiritual', 'meditation', 'consciousness', 'energy', 'soul'],
            'nature': ['nature', 'natural', 'earth', 'plant', 'tree', 'garden'],
            'permaculture': ['permaculture', 'organic', 'regenerative', 'compost'],
            'bien-etre': ['wellness', 'wellbeing', 'health', 'healing', 'peace', 'zen']
        }
        
        for theme, keywords in message_theme_keywords.items():
            if any(keyword in all_messages_text for keyword in keywords):
                themes.add(theme)
        
        # Ne PAS ajouter 'accueil' comme thème principal
        # Cela force le persona par défaut systématiquement
        
        themes_list = list(themes)
        self.logger.info(f"Extracted themes: {themes_list}")
        return themes_list
    
    def select_best_persona_with_ai(self, profile: Dict, recent_messages: List[Dict], current_message: str) -> Tuple[str, Dict]:
        """Sélectionne le meilleur persona en utilisant l'IA (Ollama via question.py)"""
        self.logger.info("🤖 Using AI to select best persona based on profile and messages")
        
        # Préparer le contexte pour l'IA
        profile_text = ""
        if profile:
            display_name = profile.get('display_name', 'Unknown')
            about = profile.get('about', 'No bio')
            nip05 = profile.get('nip05', 'No NIP-05')
            profile_text = f"Display name: {display_name}\nBio: {about}\nNIP-05: {nip05}"
        else:
            profile_text = "No profile information available"
        
        # Préparer les messages récents
        messages_text = ""
        if recent_messages:
            messages_text = "Recent messages:\n"
            for i, msg in enumerate(recent_messages[:5], 1):
                content = msg.get('content', '')[:200]  # Limiter à 200 caractères
                messages_text += f"{i}. {content}...\n"
        else:
            messages_text = "No recent messages"
        
        # Construire le prompt de sélection de persona
        personas_description = ""
        for slot, bank in self.banks_config['banks'].items():
            name = bank.get('name', 'Unknown')
            description = bank.get('description', '')
            themes = ', '.join(bank.get('themes', []))
            personas_description += f"\n{slot}. **{name}**: {description}\n   Themes: {themes}\n"
        
        selection_prompt = f"""You are an expert in persona selection for an AI assistant system.

Available personas:
{personas_description}

Visitor information:
---
Profile:
{profile_text}

{messages_text}

Current message: "{current_message}"
---

Based on the visitor's profile, recent messages, and current message, select the BEST persona (0, 1, 2, or 3) that should respond to this visitor.

Consider:
- The visitor's interests and background from their profile
- The topics they discuss in their messages
- The tone and content of their communication
- Which persona would resonate most with them

Respond with ONLY a JSON object in this format:
{{"persona": "0", "reason": "Brief explanation of why this persona is best"}}

Important: Return ONLY the JSON, no other text."""
        
        try:
            # Appeler question.py avec --json
            question_script = os.path.join(self.base_path, "Astroport.ONE", "IA", "question.py")
            if not os.path.exists(question_script):
                self.logger.warning(f"question.py not found at {question_script}, falling back to keyword method")
                return self._select_best_persona_fallback(profile, recent_messages, current_message)
            
            self.logger.info("📞 Asking AI to select best persona...")
            result = subprocess.run(
                ['python3', question_script, selection_prompt, '--json'],
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if result.returncode == 0 and result.stdout.strip():
                try:
                    response = json.loads(result.stdout)
                    ai_answer = response.get('answer', '{}')
                    
                    # Clean the AI answer: extract JSON from markdown code blocks if present
                    ai_answer_cleaned = self._extract_json_from_markdown(ai_answer)
                    
                    # Parser la réponse de l'IA
                    persona_selection = json.loads(ai_answer_cleaned)
                    selected_slot = str(persona_selection.get('persona', '3'))
                    reason = persona_selection.get('reason', 'AI selection')
                    
                    # Valider que le slot existe
                    if selected_slot not in self.banks_config['banks']:
                        self.logger.warning(f"AI selected invalid slot {selected_slot}, using default")
                        selected_slot = "3"
                    
                    selected_bank = self.banks_config['banks'][selected_slot]
                    persona_name = selected_bank.get('name', 'Unknown')
                    
                    self.logger.info(f"✅ AI selected persona {selected_slot} ({persona_name})")
                    self.logger.info(f"   Reason: {reason}")
                    
                    return selected_slot, selected_bank
                    
                except (json.JSONDecodeError, KeyError) as e:
                    self.logger.error(f"Failed to parse AI response: {e}")
                    self.logger.debug(f"AI output: {result.stdout}")
            else:
                self.logger.warning(f"AI call failed: {result.stderr}")
                
        except subprocess.TimeoutExpired:
            self.logger.warning("AI persona selection timed out (30s)")
        except Exception as e:
            self.logger.error(f"Error during AI persona selection: {e}")
        
        # Fallback sur la méthode par mots-clés
        self.logger.info("Falling back to keyword-based persona selection")
        return self._select_best_persona_fallback(profile, recent_messages, current_message)
    
    def _select_best_persona_fallback(self, profile: Dict, recent_messages: List[Dict], current_message: str) -> Tuple[str, Dict]:
        """Méthode de fallback : sélection par mots-clés si l'IA échoue"""
        self.logger.info("Using keyword-based fallback for persona selection")
        
        # Extraire les thèmes comme avant
        themes = self.extract_themes_from_profile_and_messages(profile, recent_messages, current_message)
        
        if not themes:
            selected_persona = "3"
            self.logger.info(f"No themes detected, using default persona: {selected_persona} (Holistique/Thérapeute)")
            return selected_persona, self.banks_config['banks']['3']
        
        # Calculer le score de correspondance pour chaque persona
        bank_scores = {}
        for slot, bank in self.banks_config['banks'].items():
            bank_themes = set(bank.get('themes', []))
            if not bank_themes:
                continue
            
            intersection = set(themes).intersection(bank_themes)
            if intersection:
                score = len(intersection)
                
                # Bonus pour les thèmes stratégiques
                if 'technologie' in intersection: score += 0.5
                if 'developpeur' in intersection: score += 0.5
                if 'crypto' in intersection: score += 0.4
                if 'creatif' in intersection: score += 0.4
                if 'artiste' in intersection: score += 0.3
                if 'spiritualite' in intersection: score += 0.3
                
                bank_scores[slot] = {
                    'score': score,
                    'bank': bank,
                    'matching_themes': list(intersection)
                }
        
        if not bank_scores:
            selected_persona = "3"
            self.logger.info(f"No matching personas found, using default: {selected_persona} (Holistique/Thérapeute)")
            return selected_persona, self.banks_config['banks']['3']
        
        best_slot = max(bank_scores.keys(), key=lambda x: bank_scores[x]['score'])
        best_score = bank_scores[best_slot]['score']
        best_persona_name = bank_scores[best_slot]['bank'].get('name', 'Unknown')
        
        self.logger.info(f"✅ Selected persona {best_slot} ({best_persona_name}) with score {best_score:.2f}")
        
        return best_slot, bank_scores[best_slot]['bank']
    
    def generate_persona_prompt(self, persona: Dict, visitor_message: str, visitor_themes: List[str], recent_messages: List[Dict], image_descriptions: List[str] = None) -> str:
        """Génère un prompt personnalisé basé sur le persona sélectionné"""
        persona_name = persona.get('name', 'AstroBot')
        persona_description = persona.get('description', '')
        tone = persona.get('corpus', {}).get('tone', 'amical et professionnel')
        vocabulary = persona.get('corpus', {}).get('vocabulary', [])
        
        self.logger.info(f"Generating prompt for persona: {persona_name}")
        
        # Préparer le contexte des messages récents
        recent_context = ""
        if recent_messages:
            recent_context = "\nMessages récents du visiteur:\n"
            for i, msg in enumerate(recent_messages[:5], 1):  # Limiter à 5 messages
                recent_context += f"{i}. {msg.get('content', '')[:300]}...\n"
        
        # Préparer le contexte des images
        image_context = ""
        if image_descriptions:
            image_context = "\nImages partagées par le visiteur (analysées par IA):\n"
            for i, description in enumerate(image_descriptions, 1):
                image_context += f"{i}. {description[:200]}...\n"
        
        # Créer le prompt
        prompt = f"""Tu es {persona_name}, un assistant IA d'Astroport Captain.

{persona_description}

Ton ton doit être: {tone}

Vocabulaire à privilégier: {', '.join(vocabulary[:5])}

Le visiteur a écrit: "{visitor_message}"

Thèmes détectés chez le visiteur: {', '.join(visitor_themes) if visitor_themes else 'Aucun thème spécifique détecté'}

{recent_context}{image_context}

Génère une réponse accueillante et personnalisée qui:
1. Accueille le visiteur chaleureusement
2. Répond à son message de manière pertinente
3. Si des images sont partagées, commente-les de manière pertinente selon ton persona
4. Utilise le ton et le vocabulaire appropriés à ton persona
5. Mentionne brièvement UPlanet et CopyLaRadio
6. Termine par les hashtags: #UPlanet #CopyLaRadio #AstroBot

Réponse:"""
        
        self.logger.debug(f"Generated prompt length: {len(prompt)} characters")
        return prompt
    
    def generate_response(self, pubkey: str, visitor_message: str) -> str:
        """Génère une réponse personnalisée pour le visiteur"""
        self.logger.info(f"Generating response for pubkey: {pubkey[:10]}..., message: {visitor_message[:50]}...")
        
        try:
            # S'assurer qu'Ollama est actif
            ollama_script = os.path.join(self.base_path, "Astroport.ONE", "IA", "ollama.me.sh")
            if os.path.exists(ollama_script):
                self.logger.info("Starting Ollama service")
                subprocess.run([ollama_script], capture_output=True, timeout=10)
            
            # Détecter et analyser la première image dans le message (limitation anti-spam)
            image_descriptions = []
            image_urls = self._extract_image_urls(visitor_message)
            
            if image_urls:
                # Limiter à la première image pour éviter le spam
                first_image_url = image_urls[0]
                self.logger.info(f"Found {len(image_urls)} images in message, analyzing only the first one: {first_image_url}")
                
                description = self._analyze_image_with_ai(first_image_url)
                if description:
                    image_descriptions.append(description)
                    self.logger.info(f"Image analyzed: {description[:100]}...")
                else:
                    self.logger.warning(f"Failed to analyze image: {first_image_url}")
                
                # Log si d'autres images ont été ignorées
                if len(image_urls) > 1:
                    self.logger.info(f"Ignored {len(image_urls) - 1} additional images to prevent spam")
            
            # Récupérer le profil NOSTR
            profile = self.get_nostr_profile(pubkey)
            
            # Récupérer les derniers messages
            recent_messages = self.get_recent_messages(pubkey, limit=10)
            
            # Détecter la langue du visiteur
            all_text = visitor_message
            for message in recent_messages:
                all_text += " " + message.get('content', '')
            
            target_language = self.detect_language(all_text)
            self.logger.info(f"Detected language: {target_language}")
            
            # Sélectionner le meilleur persona AVEC L'IA (au lieu des mots-clés)
            persona_slot, selected_persona = self.select_best_persona_with_ai(profile, recent_messages, visitor_message)
            
            # Extraire les thèmes pour le prompt de génération (optionnel, pour le contexte)
            themes = self.extract_themes_from_profile_and_messages(profile, recent_messages, visitor_message)
            
            # Générer le prompt personnalisé avec contexte d'images
            prompt = self.generate_persona_prompt(selected_persona, visitor_message, themes, recent_messages, image_descriptions)
            
            # Utiliser la méthode _query_ia pour générer la réponse dans la langue détectée
            response = self._query_ia(prompt, target_language=target_language)
            if response:
                self.logger.info("AI response generated successfully")
                return response
            else:
                self.logger.warning("AI response generation failed, using fallback")
                return self._generate_fallback_response(selected_persona, visitor_message, target_language, image_descriptions)
            
        except Exception as e:
            self.logger.error(f"Error generating response: {e}")
            return self._generate_fallback_response(self.banks_config['banks']['3'], visitor_message, 'fr')
    
    def _generate_fallback_response(self, persona: Dict, visitor_message: str, target_language: str = 'fr', image_descriptions: List[str] = None) -> str:
        """Génère une réponse de fallback si l'IA échoue"""
        self.logger.info("Generating fallback response")
        persona_name = persona.get('name', 'AstroBot')
        tone = persona.get('corpus', {}).get('tone', 'amical et professionnel')
        
        # Préparer le contexte des images pour les réponses de fallback
        image_context = ""
        if image_descriptions:
            image_context = f"\n\nJ'ai également analysé les images que vous avez partagées :\n"
            for i, description in enumerate(image_descriptions, 1):
                image_context += f"{i}. {description[:150]}...\n"
        
        # Réponses de fallback multilingues
        fallback_responses = {
            'fr': f"""Bonjour ! Je suis {persona_name}, l'assistant IA d'Astroport Captain.

J'ai reçu votre message : "{visitor_message}"{image_context}

Bienvenue dans notre communauté ! Je serais ravi de vous aider à découvrir UPlanet et CopyLaRadio, notre écosystème numérique souverain.

N'hésitez pas à me poser des questions sur nos projets, notre technologie ou notre communauté !

#UPlanet #CopyLaRadio #AstroBot""",
            
            'en': f"""Hello! I am {persona_name}, Astroport Captain's AI assistant.

I received your message: "{visitor_message}"{image_context}

Welcome to our community! I would be happy to help you discover UPlanet and CopyLaRadio, our sovereign digital ecosystem.

Feel free to ask me questions about our projects, technology, or community!

#UPlanet #CopyLaRadio #AstroBot""",
            
            'es': f"""¡Hola! Soy {persona_name}, el asistente IA del Capitán Astroport.

Recibí tu mensaje: "{visitor_message}"{image_context}

¡Bienvenido a nuestra comunidad! Me encantaría ayudarte a descubrir UPlanet y CopyLaRadio, nuestro ecosistema digital soberano.

¡No dudes en hacerme preguntas sobre nuestros proyectos, tecnología o comunidad!

#UPlanet #CopyLaRadio #AstroBot""",
            
            'de': f"""Hallo! Ich bin {persona_name}, der KI-Assistent von Astroport Captain.

Ich habe deine Nachricht erhalten: "{visitor_message}"{image_context}

Willkommen in unserer Community! Ich helfe dir gerne dabei, UPlanet und CopyLaRadio, unser souveränes digitales Ökosystem, zu entdecken.

Zögere nicht, mich Fragen zu unseren Projekten, Technologie oder Community zu stellen!

#UPlanet #CopyLaRadio #AstroBot""",
            
            'it': f"""Ciao! Sono {persona_name}, l'assistente IA del Capitano Astroport.

Ho ricevuto il tuo messaggio: "{visitor_message}"{image_context}

Benvenuto nella nostra comunità! Sarei felice di aiutarti a scoprire UPlanet e CopyLaRadio, il nostro ecosistema digitale sovrano.

Non esitare a farmi domande sui nostri progetti, tecnologia o comunità!

#UPlanet #CopyLaRadio #AstroBot""",
            
            'pt': f"""Olá! Sou {persona_name}, o assistente IA do Capitão Astroport.

Recebi sua mensagem: "{visitor_message}"{image_context}

Bem-vindo à nossa comunidade! Ficaria feliz em ajudá-lo a descobrir UPlanet e CopyLaRadio, nosso ecossistema digital soberano.

Não hesite em me fazer perguntas sobre nossos projetos, tecnologia ou comunidade!

#UPlanet #CopyLaRadio #AstroBot"""
        }
        
        return fallback_responses.get(target_language, fallback_responses['fr'])

def main():
    """Point d'entrée principal"""
    if len(sys.argv) != 3:
        print("Usage: python astrobot_visitor_response.py <pubkey> <message>")
        sys.exit(1)
    
    pubkey = sys.argv[1]
    message = sys.argv[2]
    
    responder = AstroBotVisitorResponder()
    response = responder.generate_response(pubkey, message)
    
    # Output only the response to stdout (no debug messages)
    print(response)

if __name__ == "__main__":
    main() 