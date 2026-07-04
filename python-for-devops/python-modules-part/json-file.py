# i have a json file, load that in code and make it work like a dictionary

# file name = data.json

# read the file
import json
# with open('data.json', 'r') as file:
#     print(file.read())
#     print(type(file.read()))

# with open('data.json', 'r') as file:
#     data = json.load(file)
#     print(data)
#     print(type(data))


# data = """{
#     "name": "John",
#     "age": 30,
#     "city": "New York"
# }"""

# print(json.loads(data))
# print(type(json.loads(data)))
    


# pen the file , load with json, modify the data, write back to the file
with open('data.json', 'r') as file:
    data = json.load(file)
    data['age'] = 31
    data['city'] = 'Los Angeles'

print(data)
with open('data-new.json', 'w') as file:
    json.dump(data, file, indent=4)

print(data)
print(type(data))