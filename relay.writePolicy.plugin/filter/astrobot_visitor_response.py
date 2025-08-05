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
from typing import Dict, List, Optional, Tuple

class AstroBotVisitorResponder:
    def __init__(self):
        self.base_path = os.path.expanduser("~/.zen")
        self.astrobot_path = os.path.join(self.base_path, "workspace", "OC2UPlanet", "AstroBot")
        self.workspace_path = os.path.join(self.astrobot_path, "workspace")
        self.banks_config_file = os.path.join(self.workspace_path, "memory_banks_config.json")
        
        # Relais NOSTR publics pour récupérer les profils
        self.nostr_relays = [
            "wss://relay.damus.io",
            "wss://nos.lol",
            "wss://relay.snort.social",
            "wss://relay.nostr.band"
        ]
        
        # Charger la configuration des personas
        self.banks_config = self._load_banks_config()
        
    def _load_banks_config(self) -> Dict:
        """Charge la configuration des personas d'AstroBot"""
        if os.path.exists(self.banks_config_file):
            try:
                with open(self.banks_config_file, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except Exception as e:
                print(f"Erreur lors du chargement de la config: {e}", file=sys.stderr)
        
        # Configuration par défaut si le fichier n'existe pas
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
    
    def get_nostr_profile(self, pubkey: str) -> Optional[Dict]:
        """Récupère le profil NOSTR d'un utilisateur depuis les relais publics"""
        try:
            profile_data = {}
            
            # Essayer d'utiliser nostr-tools si disponible
            try:
                cmd = f"nostr-tools profile {pubkey}"
                result = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=10)
                if result.returncode == 0:
                    profile_data = json.loads(result.stdout)
                    return profile_data
            except:
                pass
            
            # Fallback: essayer avec curl et une API NOSTR
            try:
                api_url = f"https://api.nostr.band/v0/profile/{pubkey}"
                response = requests.get(api_url, timeout=10)
                if response.status_code == 200:
                    data = response.json()
                    if 'profile' in data:
                        return data['profile']
            except:
                pass
            
            # Fallback: essayer avec une autre API
            try:
                api_url = f"https://api.snort.social/v1/profile/{pubkey}"
                response = requests.get(api_url, timeout=10)
                if response.status_code == 200:
                    return response.json()
            except:
                pass
            
            return profile_data
        except Exception as e:
            print(f"Erreur lors de la récupération du profil: {e}", file=sys.stderr)
            return None
    
    def extract_themes_from_profile(self, profile: Dict, message: str) -> List[str]:
        """Extrait les thèmes pertinents du profil et du message"""
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
                'technologie': ['dev', 'tech', 'programming', 'crypto', 'blockchain', 'nostr', 'developer', 'engineer', 'software'],
                'creatif': ['art', 'music', 'artist', 'creative', 'design', 'craft', 'maker', 'creator', 'musician'],
                'nature': ['nature', 'permaculture', 'ecology', 'sustainable', 'organic', 'garden', 'farm', 'environment'],
                'spiritualite': ['spiritual', 'meditation', 'yoga', 'healing', 'wellness', 'mindfulness', 'consciousness'],
                'souverainete': ['freedom', 'liberty', 'sovereign', 'decentralized', 'autonomy', 'independence', 'self-sufficient']
            }
            
            for theme, keywords in theme_keywords.items():
                if any(keyword in bio for keyword in keywords):
                    themes.add(theme)
        
        # Analyser le message
        message_lower = message.lower()
        message_themes = {
            'technologie': ['tech', 'crypto', 'nostr', 'blockchain', 'dev', 'programming', 'code', 'software', 'computer'],
            'creatif': ['art', 'music', 'creative', 'design', 'craft', 'draw', 'paint', 'write', 'compose'],
            'nature': ['nature', 'ecology', 'sustainable', 'organic', 'garden', 'plant', 'earth', 'environment'],
            'spiritualite': ['spiritual', 'meditation', 'healing', 'wellness', 'peace', 'mind', 'soul', 'energy'],
            'souverainete': ['freedom', 'liberty', 'sovereign', 'decentralized', 'free', 'independent', 'autonomous']
        }
        
        for theme, keywords in message_themes.items():
            if any(keyword in message_lower for keyword in keywords):
                themes.add(theme)
        
        # Ajouter des thèmes basés sur la langue du message
        if any(word in message_lower for word in ['bonjour', 'salut', 'hello', 'hi']):
            themes.add('accueil')  # Thème d'accueil pour les messages simples
        
        return list(themes)
    
    def select_best_persona(self, themes: List[str]) -> Tuple[str, Dict]:
        """Sélectionne le meilleur persona basé sur les thèmes"""
        if not themes or themes == ['accueil']:
            # Par défaut, utiliser le persona Holistique qui est le plus accueillant
            return "3", self.banks_config['banks']['3']
        
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
            return "3", self.banks_config['banks']['3']
        
        # Sélectionner le persona avec le meilleur score
        best_slot = max(bank_scores.keys(), key=lambda x: bank_scores[x]['score'])
        return best_slot, bank_scores[best_slot]['bank']
    
    def generate_persona_prompt(self, persona: Dict, visitor_message: str, visitor_themes: List[str]) -> str:
        """Génère un prompt personnalisé basé sur le persona sélectionné"""
        persona_name = persona.get('name', 'AstroBot')
        persona_description = persona.get('description', '')
        tone = persona.get('corpus', {}).get('tone', 'amical et professionnel')
        vocabulary = persona.get('corpus', {}).get('vocabulary', [])
        
        # Créer le prompt
        prompt = f"""Tu es {persona_name}, un assistant IA d'Astroport Captain.

{persona_description}

Ton ton doit être: {tone}

Vocabulaire à privilégier: {', '.join(vocabulary[:5])}

Le visiteur a écrit: "{visitor_message}"

Thèmes détectés chez le visiteur: {', '.join(visitor_themes) if visitor_themes else 'Aucun thème spécifique détecté'}

Génère une réponse accueillante et personnalisée qui:
1. Accueille le visiteur chaleureusement
2. Répond à son message de manière pertinente
3. Utilise le ton et le vocabulaire appropriés à ton persona
4. Mentionne brièvement UPlanet et CopyLaRadio
5. Termine par les hashtags: #UPlanet #CopyLaRadio #AstroBot

Réponse:"""
        
        return prompt
    
    def generate_response(self, pubkey: str, visitor_message: str) -> str:
        """Génère une réponse personnalisée pour le visiteur"""
        try:
            # S'assurer qu'Ollama est actif
            ollama_script = os.path.join(self.base_path, "Astroport.ONE", "IA", "ollama.me.sh")
            if os.path.exists(ollama_script):
                subprocess.run([ollama_script], capture_output=True, timeout=10)
            
            # Récupérer le profil NOSTR
            profile = self.get_nostr_profile(pubkey)
            
            # Extraire les thèmes
            themes = self.extract_themes_from_profile(profile, visitor_message)
            
            # Sélectionner le meilleur persona
            persona_slot, selected_persona = self.select_best_persona(themes)
            
            # Générer le prompt personnalisé
            prompt = self.generate_persona_prompt(selected_persona, visitor_message, themes)
            
            # Utiliser question.py pour générer la réponse
            question_script = os.path.join(self.base_path, "Astroport.ONE", "IA", "question.py")
            if os.path.exists(question_script):
                cmd = [
                    sys.executable, question_script,
                    prompt,
                    "--pubkey", pubkey
                ]
                
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
                if result.returncode == 0:
                    response = result.stdout.strip()
                    # Extraire la dernière ligne qui contient la réponse
                    lines = response.split('\n')
                    for line in reversed(lines):
                        if line.strip() and not line.startswith('DEBUG') and not line.startswith('INFO') and not line.startswith('Failed'):
                            return line.strip()
            
            # Fallback si question.py échoue
            return self._generate_fallback_response(selected_persona, visitor_message)
            
        except Exception as e:
            print(f"Erreur lors de la génération de la réponse: {e}", file=sys.stderr)
            return self._generate_fallback_response(self.banks_config['banks']['3'], visitor_message)
    
    def _generate_fallback_response(self, persona: Dict, visitor_message: str) -> str:
        """Génère une réponse de fallback si l'IA échoue"""
        persona_name = persona.get('name', 'AstroBot')
        tone = persona.get('corpus', {}).get('tone', 'amical et professionnel')
        
        return f"""Bonjour ! Je suis {persona_name}, l'assistant IA d'Astroport Captain.

J'ai reçu votre message : "{visitor_message}"

Bienvenue dans notre communauté ! Je serais ravi de vous aider à découvrir UPlanet et CopyLaRadio, notre écosystème numérique souverain.

N'hésitez pas à me poser des questions sur nos projets, notre technologie ou notre communauté !

#UPlanet #CopyLaRadio #AstroBot"""

def main():
    """Point d'entrée principal"""
    if len(sys.argv) != 3:
        print("Usage: python astrobot_visitor_response.py <pubkey> <message>")
        sys.exit(1)
    
    pubkey = sys.argv[1]
    message = sys.argv[2]
    
    responder = AstroBotVisitorResponder()
    response = responder.generate_response(pubkey, message)
    
    print(response)

if __name__ == "__main__":
    main() 