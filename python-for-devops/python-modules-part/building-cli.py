import argparse

# parser = argparse.ArgumentParser()
# parser.add_argument('name', help='the name to greet')
# parser.add_argument('age', help='the age to greet')
# parser.add_argument('city', help='the city to greet')
# args = parser.parse_args()

# print(f'Hello, {args.name}! You are {args.age} years old and you live in {args.city}.')

# # demo named args -> --name and --age and --city
# parser = argparse.ArgumentParser()
# parser.add_argument('--name', help='the name to greet')
# parser.add_argument('--age', help='the age to greet')
# parser.add_argument('--city', help='the city to greet')
# args = parser.parse_args()

# print(f'Hello, {args.name}! You are {args.age} years old and you live in {args.city}.')


# demo of choice, options -> --mode and --name and --age and --city
parser = argparse.ArgumentParser()
parser.add_argument('--mode', help='the mode to run', choices=['greet', 'bye'])
parser.add_argument('--name', help='the name to greet')
parser.add_argument('--age', help='the age to greet')
parser.add_argument('--city', help='the city to greet')
args = parser.parse_args()

if args.mode == 'greet':
    print(f'Hello, {args.name}! You are {args.age} years old and you live in {args.city}.')
elif args.mode == 'bye':
    print(f'Bye, {args.name}! You are {args.age} years old and you live in {args.city}.')