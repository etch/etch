# Be sure to restart your server when you modify this file.

# Your secret key is used for verifying the integrity of signed cookies.
# If you change this key, all old signed cookies will become invalid!

# Make sure the secret is at least 30 characters and all random,
# no regular words or you'll be exposed to dictionary attacks.
# You can use `rake secret` to generate a secure secret key.

# Make sure your secret_key_base is kept private
# if you're sharing your code publicly.
Server::Application.config.secret_key_base = '37a509b68cef3ce8f16fd3e32133ded998493f73e038cbaf6845c6eb147a4ffc8aaf14639884d26037d836d804e03b9c1bd1f110bdd310f4e7ef8a502d8b8bc5'
