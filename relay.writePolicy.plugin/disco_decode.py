#!/usr/bin/env python3
import os
import subprocess
import urllib.parse
import tempfile
import sys
import argparse

def decode_private_key(player_email, uplanetname):
    """Decrypts and combines shares to decode a Nostr private key from files."""

    nostr_dir = os.path.join(os.path.expanduser("~"), ".zen", "game", "nostr", player_email)
    ssss_mid_captain_enc = os.path.join(nostr_dir, "ssss.mid.captain.enc")
    ssss_tail_uplanet_asc = os.path.join(nostr_dir, "ssss.tail.uplanet.asc")
    secret_dunikey = os.path.join(os.path.expanduser("~"), ".zen", "game", "players", ".current", "secret.dunikey")

    tmp_mid = None
    tmp_tail = None
    try:
        # Manually create and manage temporary files
        tmp_mid_file = tempfile.NamedTemporaryFile(delete=True, mode='w+t') #open it in text mode and enable writing for ssss-combine
        tmp_tail_file = tempfile.NamedTemporaryFile(delete=True, mode='w+t')  # Ensure tail file can be read too
        tmp_combined_file = tempfile.NamedTemporaryFile(delete=True, mode='w+t') # temp file to store the combined content

        tmp_mid = tmp_mid_file.name
        tmp_tail = tmp_tail_file.name
        tmp_combined = tmp_combined_file.name #The combined file

        # Expand the path here
        natools_path = os.path.expanduser("~/.zen/Astroport.ONE/tools/natools.py")

        print(f"Decrypting middle part using natools.py with path: {natools_path}", file=sys.stderr) #log

        try:
            subprocess.run(
                [natools_path, "decrypt", "-f", "pubsec", "-i", ssss_mid_captain_enc, "-k", secret_dunikey, "-o", tmp_mid],
                check=True, capture_output=True, text=True, cwd=os.path.dirname(os.path.abspath(__file__))
            )
            print(f"Successfully decrypted middle part. Output file: {tmp_mid}", file=sys.stderr) #log
        except subprocess.CalledProcessError as e:
            print(f"Error decrypting middle part: {e.stderr}", file=sys.stderr)
            return None

        print(f"Decrypting tail part using gpg with file: {ssss_tail_uplanet_asc}", file=sys.stderr) #log
        try:
            result = subprocess.run(
                ["gpg", "-d", "--batch", "--passphrase", uplanetname, ssss_tail_uplanet_asc],
                check=True, capture_output=True, text=True
            )
            # Now reading from result.stdout instead of creating a file

            tail_output = result.stdout
            print(f"gpg decryption Output: {tail_output}", file=sys.stderr) #log
            if not tail_output:
                print("GPG decryption produced empty output.", file=sys.stderr)
                return None

            # Write output to temp file
            tmp_tail_file.write(tail_output)  # Write to the temporary file
            tmp_tail_file.flush()
            tmp_tail_file.seek(0) # Go back to the beginning

        except subprocess.CalledProcessError as e:
            print(f"Error decrypting tail part: {e.stderr}", file=sys.stderr)
            return None

        print(f"Combining shares using ssss-combine with tmp_mid file: {tmp_mid}", file=sys.stderr) #log

        try:

            # Rewind the file pointer to the beginning of the file
            tmp_mid_file.seek(0)
            tmp_tail_file.seek(0)

            # Read the content of the tmp_mid file for logging
            tmp_mid_content = tmp_mid_file.read()
            tmp_tail_content = tmp_tail_file.read()
            print(f"Content of tmp_mid file being passed to ssss-combine:\n{tmp_mid_content}", file=sys.stderr)

            with open(tmp_combined, 'w') as combined_file:

                combined_content = tmp_mid_content + "\n" + tmp_tail_content
                combined_file.write(combined_content)
                combined_file.flush()
                combined_file.seek(0) #Rewind the file

            print(f"Combining shares using ssss-combine with tmp_combined file: {tmp_combined}", file=sys.stderr) #log

            process = subprocess.Popen(
                ["ssss-combine", "-t", "2", "-q"],
                stdin=open(tmp_combined, 'r'),  # Pass the content via temp file
                stderr=subprocess.PIPE,
                stdout=subprocess.PIPE,
                text=True, cwd=os.path.dirname(os.path.abspath(__file__))
            )

            combined_output, combined_errors = process.communicate()

            if process.returncode != 0:
                print(f"ssss-combine returned non-zero exit code: {process.returncode}", file=sys.stderr)
                print(f"ssss-combine error output: {combined_errors}", file=sys.stderr)
                return None

            combined_output = combined_output.strip()

            print(f"Successfully combined shares. Combined output: {combined_output}", file=sys.stderr)

        except subprocess.CalledProcessError as e:
            print(f"Error combining shares: {e.stderr.strip()}", file=sys.stderr)
            return None
        except FileNotFoundError:
            print("Error ssss-combine command not found.", file=sys.stderr)
            return None

        try:
            parts = combined_output.split()
            if len(parts) < 4:
                print("Error: Invalid combined output format.", file=sys.stderr)
                return None
            s = urllib.parse.unquote_plus(parts[0].split("=")[1])
            salt = urllib.parse.unquote_plus(parts[1].split("=")[1])
            p = urllib.parse.unquote_plus(parts[2].split("=")[1])
            pepper = urllib.parse.unquote_plus(parts[3].split("=")[1])

            if not s.startswith("/"):
                print("Error: s does not start with /", file=sys.stderr)
                return None
            return (s, salt, p, pepper)
        except Exception as e:
            print(f"Error parsing combined output: {e}", file=sys.stderr)
            return None

    except Exception as e:
        print(f"An unexpected error occurred: {e}", file=sys.stderr)
        return None
    finally:
        # Ensure temporary files are closed and deleted, even if errors occur
        if tmp_mid_file:
            tmp_mid_file.close()
        if tmp_tail_file:
            tmp_tail_file.close()
        if tmp_combined_file:
            tmp_combined_file.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Decrypt and combine shares to decode a Nostr private key.")
    parser.add_argument("player_email", help="The email address associated with the player/account.")
    parser.add_argument("uplanetname", help="The passphrase for the tail decryption.")

    args = parser.parse_args()

    result = decode_private_key(args.player_email, args.uplanetname)

    if result:
        s, salt, p, pepper = result
        print("Decoded successfully:")
        print(f"  s: {s}")
        print(f"  salt: {salt}")
        print(f"  p: {p}")
        print(f"  pepper: {pepper}")
    else:
        print("Decoding failed.")
