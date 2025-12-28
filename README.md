# dot-files
Configuration files for different linux/gnu based tooling

## Local Deployment & Setup

### 1. Clone the Repository
```bash
git clone <repository-url> ~/Github/Github_desktop/dot-files
cd ~/Github/Github_desktop/dot-files
```

### 2. Set Up Environment Variables

This repository uses a `.env` file to store sensitive information like API keys and credentials.

```bash
# Copy the example file
cp .env.example .env

# Edit .env and add your actual credentials
vim .env  # or use your preferred editor
```

**Required environment variables:**
- `AWS_ACCESS_KEY_ID` - Your AWS access key
- `AWS_SECRET_ACCESS_KEY` - Your AWS secret key
- `AWS_DEFAULT_REGION` - Your preferred AWS region (default: us-east-1)

**Optional API keys:**
- `OPENAI_API_KEY` - For OpenAI API access
- `GOOGLE_API_KEY` - For Google API access
- `ANTHROPIC_API_KEY` - For Anthropic Claude API access

### 3. Link Configuration Files

Create a symbolic link to use the zsh configuration:
```bash
ln -sf ~/Github/Github_desktop/dot-files/shell/.zshrc ~/.zshrc
```

Or manually source it in your existing `.zshrc`:
```bash
echo 'source ~/Github/Github_desktop/dot-files/shell/.zshrc' >> ~/.zshrc
```

### 4. Reload Your Shell
```bash
source ~/.zshrc
```

The `.env` file will be automatically loaded when you start a new shell session.

## Security Notes

- **Never commit the `.env` file** - It's already in `.gitignore`
- The `.env.example` file is a template showing required variables
- AWS credentials and other secrets are stored only in `.env`
- Keep your `.env` file permissions restricted: `chmod 600 .env`

## File Structure

```
.
├── .env                    # Your secrets (never committed)
├── .env.example            # Template for required variables
├── .gitignore              # Excludes .env and credentials
├── shell/
│   ├── .zshrc             # Main shell configuration
│   ├── aliases.zsh        # Shell aliases
│   ├── exports.zsh        # Environment exports
│   ├── functions.zsh      # Custom functions
│   ├── load-env.zsh       # Loads .env file
│   ├── path.zsh           # PATH configuration
│   └── security.zsh       # Security tools
└── scripts/               # Utility scripts
```

## Troubleshooting

If environment variables aren't loading:
1. Check that `.env` exists in the repository root
2. Verify `load-env.zsh` is being sourced in `shell/.zshrc`
3. Reload your shell: `source ~/.zshrc`
4. Test manually: `source ~/Github/Github_desktop/dot-files/shell/load-env.zsh`
