from github import Github
import os

def check_compliance(repo):
    # Add your compliance checks here
    # Example: Check if the repository has a specific file
    if "LICENSE" not in [file.name for file in repo.get_contents('')]:
        print(f"Repository {repo.name} is out of compliance: No LICENSE file.")

def main():
    g = Github(os.getenv('GITHUB_TOKEN'))
    org = g.get_organization(os.getenv('ORG_NAME'))
    mode = os.getenv('MODE')

    repos = org.get_repos()

    # Limit to first five repositories if in debug mode
    if mode == 'debug':
        repos = repos[:5]

    for repo in repos:
        check_compliance(repo)

if __name__ == "__main__":
    main()
