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
    
    def get_recent_messages(self, pubkey: str, limit: int = 10) -> List[Dict]:
        """Récupère les derniers messages d'un utilisateur depuis strfry"""
        self.logger.info(f"Fetching {limit} recent messages for pubkey: {pubkey[:10]}...")
        try:
            # Utiliser strfry scan pour récupérer les derniers messages
            strfry_path = os.path.join(self.base_path, "strfry")
            if not os.path.exists(strfry_path):
                self.logger.warning("strfry not found, cannot fetch recent messages")
                return []
            
            # Construire la commande strfry scan
            scan_filter = json.dumps({
                "authors": [pubkey],
                "kinds": [1],
                "limit": limit
            })
            
            cmd = [os.path.join(strfry_path, "strfry"), "scan", scan_filter]
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
            
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
                
                self.logger.info(f"Retrieved {len(messages)} recent messages")
                return messages
            else:
                self.logger.debug(f"strfry scan failed: {result.stderr}")
                return []
                
        except Exception as e:
            self.logger.error(f"Error retrieving recent messages: {e}")
            return []
    
    def extract_themes_from_profile_and_messages(self, profile: Dict, messages: List[Dict], current_message: str) -> List[str]:
        """Extrait les thèmes pertinents du profil, des messages récents et du message actuel"""
        self.logger.info("Extracting themes from profile, recent messages and current message")
        themes = set()
        
        # Extraire les thèmes du profil
        if profile:
            # Analyser le nom d'affichage
            display_name = profile.get('display_name', '').lower()
            if any(theme in display_name for theme in ['dev', 'tech', 'crypto', 'art', 'music', 'nature']):
                themes.update(['technologie', 'creatif', 'nature'])
            
            # Analyser la bio
            bio = profile.get('about', '').lower()
            theme_keywords = {
                'technologie': ['dev', 'tech', 'programming', 'crypto', 'blockchain', 'nostr', 'developer', 'engineer', 'software', 'code', 'computer', 'digital'],
                'creatif': ['art', 'music', 'artist', 'creative', 'design', 'craft', 'maker', 'creator', 'musician', 'painter', 'writer', 'composer'],
                'nature': ['nature', 'permaculture', 'ecology', 'sustainable', 'organic', 'garden', 'farm', 'environment', 'earth', 'green', 'eco'],
                'spiritualite': ['spiritual', 'meditation', 'yoga', 'healing', 'wellness', 'mindfulness', 'consciousness', 'zen', 'peace', 'soul'],
                'souverainete': ['freedom', 'liberty', 'sovereign', 'decentralized', 'autonomy', 'independence', 'self-sufficient', 'free', 'independent']
            }
            
            for theme, keywords in theme_keywords.items():
                if any(keyword in bio for keyword in keywords):
                    themes.add(theme)
        
        # Analyser les messages récents
        all_messages_text = current_message.lower()
        for message in messages:
            all_messages_text += " " + message.get('content', '').lower()
        
        message_themes = {
            'technologie': ['tech', 'crypto', 'nostr', 'blockchain', 'dev', 'programming', 'code', 'software', 'computer', 'digital', 'ai', 'machine learning'],
            'creatif': ['art', 'music', 'creative', 'design', 'craft', 'draw', 'paint', 'write', 'compose', 'artist', 'creative', 'design'],
            'nature': ['nature', 'ecology', 'sustainable', 'organic', 'garden', 'plant', 'earth', 'environment', 'green', 'eco', 'permaculture'],
            'spiritualite': ['spiritual', 'meditation', 'healing', 'wellness', 'peace', 'mind', 'soul', 'energy', 'zen', 'consciousness'],
            'souverainete': ['freedom', 'liberty', 'sovereign', 'decentralized', 'free', 'independent', 'autonomous', 'self-sufficient']
        }
        
        for theme, keywords in message_themes.items():
            if any(keyword in all_messages_text for keyword in keywords):
                themes.add(theme)
        
        # Ajouter des thèmes basés sur la langue du message
        if any(word in current_message.lower() for word in ['bonjour', 'salut', 'hello', 'hi', 'hey']):
            themes.add('accueil')  # Thème d'accueil pour les messages simples
        
        themes_list = list(themes)
        self.logger.info(f"Extracted themes: {themes_list}")
        return themes_list
    
    def select_best_persona(self, themes: List[str]) -> Tuple[str, Dict]:
        """Sélectionne le meilleur persona basé sur les thèmes"""
        self.logger.info(f"Selecting best persona for themes: {themes}")
        
        if not themes or themes == ['accueil']:
            # Par défaut, utiliser le persona Holistique qui est le plus accueillant
            selected_persona = "3"
            self.logger.info(f"Using default persona: {selected_persona} (Holistique)")
            return selected_persona, self.banks_config['banks']['3']
        
        # Calculer le score de correspondance pour chaque persona
        bank_scores = {}
        for slot, bank in self.banks_config['banks'].items():
            bank_themes = set(bank.get('themes', []))
            if not bank_themes:
                continue
            
            # Calculer l'intersection
            intersection = set(themes).intersection(bank_themes)
            if intersection:
                score = len(intersection) / len(bank_themes)
                # Bonus pour les thèmes forts
                if 'technologie' in intersection:
                    score += 0.2
                if 'creatif' in intersection:
                    score += 0.15
                if 'spiritualite' in intersection:
                    score += 0.1
                
                bank_scores[slot] = {
                    'score': score,
                    'bank': bank,
                    'matching_themes': list(intersection)
                }
        
        if not bank_scores:
            # Aucune correspondance, utiliser le persona Holistique
            selected_persona = "3"
            self.logger.info(f"No matching personas found, using default: {selected_persona} (Holistique)")
            return selected_persona, self.banks_config['banks']['3']
        
        # Sélectionner le persona avec le meilleur score
        best_slot = max(bank_scores.keys(), key=lambda x: bank_scores[x]['score'])
        best_score = bank_scores[best_slot]['score']
        matching_themes = bank_scores[best_slot]['matching_themes']
        
        self.logger.info(f"Selected persona {best_slot} with score {best_score:.2f}, matching themes: {matching_themes}")
        return best_slot, bank_scores[best_slot]['bank']
    
    def generate_persona_prompt(self, persona: Dict, visitor_message: str, visitor_themes: List[str], recent_messages: List[Dict]) -> str:
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
        
        # Créer le prompt
        prompt = f"""Tu es {persona_name}, un assistant IA d'Astroport Captain.

{persona_description}

Ton ton doit être: {tone}

Vocabulaire à privilégier: {', '.join(vocabulary[:5])}

Le visiteur a écrit: "{visitor_message}"

Thèmes détectés chez le visiteur: {', '.join(visitor_themes) if visitor_themes else 'Aucun thème spécifique détecté'}

{recent_context}

Génère une réponse accueillante et personnalisée qui:
1. Accueille le visiteur chaleureusement
2. Répond à son message de manière pertinente
3. Utilise le ton et le vocabulaire appropriés à ton persona
4. Mentionne brièvement UPlanet et CopyLaRadio
5. Termine par les hashtags: #UPlanet #CopyLaRadio #AstroBot

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
            
            # Extraire les thèmes
            themes = self.extract_themes_from_profile_and_messages(profile, recent_messages, visitor_message)
            
            # Sélectionner le meilleur persona
            persona_slot, selected_persona = self.select_best_persona(themes)
            
            # Générer le prompt personnalisé
            prompt = self.generate_persona_prompt(selected_persona, visitor_message, themes, recent_messages)
            
            # Utiliser la méthode _query_ia pour générer la réponse dans la langue détectée
            response = self._query_ia(prompt, target_language=target_language)
            if response:
                self.logger.info("AI response generated successfully")
                return response
            else:
                self.logger.warning("AI response generation failed, using fallback")
                return self._generate_fallback_response(selected_persona, visitor_message, target_language)
            
        except Exception as e:
            self.logger.error(f"Error generating response: {e}")
            return self._generate_fallback_response(self.banks_config['banks']['3'], visitor_message, 'fr')
    
    def _generate_fallback_response(self, persona: Dict, visitor_message: str, target_language: str = 'fr') -> str:
        """Génère une réponse de fallback si l'IA échoue"""
        self.logger.info("Generating fallback response")
        persona_name = persona.get('name', 'AstroBot')
        tone = persona.get('corpus', {}).get('tone', 'amical et professionnel')
        
        # Réponses de fallback multilingues
        fallback_responses = {
            'fr': f"""Bonjour ! Je suis {persona_name}, l'assistant IA d'Astroport Captain.

J'ai reçu votre message : "{visitor_message}"

Bienvenue dans notre communauté ! Je serais ravi de vous aider à découvrir UPlanet et CopyLaRadio, notre écosystème numérique souverain.

N'hésitez pas à me poser des questions sur nos projets, notre technologie ou notre communauté !

#UPlanet #CopyLaRadio #AstroBot""",
            
            'en': f"""Hello! I am {persona_name}, Astroport Captain's AI assistant.

I received your message: "{visitor_message}"

Welcome to our community! I would be happy to help you discover UPlanet and CopyLaRadio, our sovereign digital ecosystem.

Feel free to ask me questions about our projects, technology, or community!

#UPlanet #CopyLaRadio #AstroBot""",
            
            'es': f"""¡Hola! Soy {persona_name}, el asistente IA del Capitán Astroport.

Recibí tu mensaje: "{visitor_message}"

¡Bienvenido a nuestra comunidad! Me encantaría ayudarte a descubrir UPlanet y CopyLaRadio, nuestro ecosistema digital soberano.

¡No dudes en hacerme preguntas sobre nuestros proyectos, tecnología o comunidad!

#UPlanet #CopyLaRadio #AstroBot""",
            
            'de': f"""Hallo! Ich bin {persona_name}, der KI-Assistent von Astroport Captain.

Ich habe deine Nachricht erhalten: "{visitor_message}"

Willkommen in unserer Community! Ich helfe dir gerne dabei, UPlanet und CopyLaRadio, unser souveränes digitales Ökosystem, zu entdecken.

Zögere nicht, mich Fragen zu unseren Projekten, Technologie oder Community zu stellen!

#UPlanet #CopyLaRadio #AstroBot""",
            
            'it': f"""Ciao! Sono {persona_name}, l'assistente IA del Capitano Astroport.

Ho ricevuto il tuo messaggio: "{visitor_message}"

Benvenuto nella nostra comunità! Sarei felice di aiutarti a scoprire UPlanet e CopyLaRadio, il nostro ecosistema digitale sovrano.

Non esitare a farmi domande sui nostri progetti, tecnologia o comunità!

#UPlanet #CopyLaRadio #AstroBot""",
            
            'pt': f"""Olá! Sou {persona_name}, o assistente IA do Capitão Astroport.

Recebi sua mensagem: "{visitor_message}"

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