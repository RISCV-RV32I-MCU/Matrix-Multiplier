# Lets make a function to display the cost per person vs how many people be.
import matplotlib.pyplot as plt
cost_flight = 330 # each person has a cost of flights so it would be x450 where x is the number of people
cost_female_hotal_room = 1100 #there will only ever be one of this cost
cost_per_male_hotal_room = 1000 #each male hotel room can fit 4 to 5 people
cost_of_registration = 750 #there will only ever be one of this cost
cost_of_car = 800 #each car can fight roughly 5 to 6 people
cost_of_gas = 400 #each car will need gas

def cost_per_person(x):

    total_cost = (
    (cost_of_registration + cost_female_hotal_room)
    + (x * cost_flight)
    + (cost_per_male_hotal_room * ((max(x - 6, 1) // 5)))
    + (cost_of_car * ((x + 4) // 5))
    + (cost_of_gas * ((x + 4) // 5))
    - 10000
    )
    print(total_cost / x)

    return total_cost / x

x = [i for i in range(15, 25)]
y = [cost_per_person(i) for i in x]

plt.plot(x, y)
plt.xlabel('Number of People')
plt.ylabel('Cost per Person')
plt.title('Cost per Person vs Number of People')
plt.show()