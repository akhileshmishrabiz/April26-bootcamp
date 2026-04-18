# Akhilesh Mishra - DevOps Portfolio

A modern Flask-based portfolio website showcasing DevOps expertise, educational programs, and professional achievements.

## Color Palette

This portfolio uses a high-contrast complementary color scheme:

| Color | Hex | Usage |
|-------|-----|-------|
| Primary Teal | `#348888` | Headers, backgrounds |
| Accent Teal | `#22BABB` | Links, buttons |
| Light Teal | `#9EF8EE` | Hover effects, highlights |
| Orange | `#FA7F08` | CTAs, badges |
| Red-Orange | `#F24405` | Accents, important elements |

## Installation

1. Install dependencies:
```bash
pip install -r requirements.txt
```

## Running the App

1. Start the Flask development server:
```bash
python app.py
```

2. Open your browser and navigate to:
```
http://localhost:5000
```

## Project Structure

```
app/
├── app.py                 # Flask application
├── requirements.txt       # Python dependencies
├── templates/
│   └── index.html        # Main portfolio page
└── static/
    └── style.css         # Styles with color palette
```

## Features

- Responsive design for all devices
- Modern gradient backgrounds using the color palette
- Animated hero section
- Professional highlights and achievements
- Program offerings showcase
- Social media and platform links
- Call-to-action section

## Customization

To customize the content, edit the `profile` dictionary in `app.py`.


# Deployment on ece

- install git
- install nginx

```bash

sudo yum install git

git clone <your app repo>

sudo apt install nginx -y
```


## Running the app

```bash
# cretae a virtual env
python3 -m venv .venv

# activate the virtual env

source .venv/bin/activate

# in app folder


python3 app.py


# when using gunicor, comment the above command and use this

gunicorn app:app &
```
