# asdf env need to be fetched from runtime

import os

print(os.getenv('asdfs','default value'))
# print the value of the USER environment variable


# subprocess -> run a command and get the output
import subprocess

result = subprocess.run(['ls','-l'], capture_output=True, text=True)
# print(type(result.stdout))

print(result.stdout.splitlines()[1].split()[-1])

# list -> string , string -> list, also list, string and dict manipulation

