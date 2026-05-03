from flask import Flask, render_template

app = Flask(__name__)

@app.route('/')
def home():
    # Portfolio data
    profile = {
        'name': 'Akhilesh Mishra',
        'title': 'Senior DevOps Engineer & Educator',
        'tagline': 'Building Living Devops - Training the next generation of DevOps, SRE & Platform Engineers',
        'experience': '13+ years in Private & Public Cloud (GCP & AWS)',
        'links': {
            'substack': 'https://akhileshmishra.substack.com/',
            'github': 'https://github.com/akhileshmishrabiz',
            'medium': 'https://medium.com/@akhilesh-mishra',
            'linkedin': 'https://in.linkedin.com/in/akhilesh-mishra-0ab886124',
            'website': 'https://livingdevops.com/',
            'twitter': 'https://x.com/livingdevops',
            'topmate': 'https://topmate.io/akhilesh_mishra'
        },
        'highlights': [
            'Mentored 400+ professionals to transition into DevOps',
            'Creator of Real-World Project-Based DevOps Bootcamps',
            '21.6K+ followers on X (Twitter)',
            'Active content creator on Substack and Medium'
        ],
        'offerings': [
            {
                'title': '25-Week AWS DevOps + MLOPS + AIOPS Bootcamp',
                'description': 'Comprehensive bootcamp covering AWS cloud, DevOps practices, and AI/ML operations'
            },
            {
                'title': '16-Week Azure DevOps Bootcamp',
                'description': 'Real-world, project-based training for Azure DevOps professionals'
            },
            {
                'title': 'One-on-One Mentoring',
                'description': 'Personalized guidance for DevOps career transitions and skill development'
            }
        ]
    }

    return render_template('index.html', profile=profile)

if __name__ == '__main__':
    # start the flask app 
    app.run( host='0.0.0.0', port=8000)
