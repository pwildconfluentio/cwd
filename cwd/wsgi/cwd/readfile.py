with open("adcontent.txt") as file:
    addata = file.readlines()
    addata = [ad.rstrip() for ad in addata]
for l in addata:
    a,b,c = l.split(",")
    print(b)
