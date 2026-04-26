- Netwroking done
- take the app + db from day 2 and deploy it with autoscaling + ALB 
- RDS database - postgres 
- Autoscaling group
- launch template  - template of running EC2 -> os + packages + run command
- restore the database from bckup 
- ALB + route53 domain mapping
- Aws cert ma nager for ssl cert + vlaideation
- Runing app with https that can scale 
- implement scaling polices 


Public subnet (both of them) -> ALB 
Private subnet for autoscaling group (both of them for HA)
RDS subnet for rds instance 

security group 
for  ALB -> i will only allow port 80- and 443 (https and https) -> from public all ips
for ASG -> only al;low the inbound on app port 8000  -> only allowwed from ALB (ALB SG)
for RDS -> allow port 5432(postgres port) -> only allow from ASG SG


user:
pass: Admin1234
host: aprilasgapp.cvik8accw2tk.ap-south-1.rds.amazonaws.com
port:
dbname: 
<!-- DB_LINK=postgresql://postgres:postgres@localhost:5432/mydb" -->

DB_LINK=postgresql://postgres:Admin1234@aprilasgapp.cvik8accw2tk.ap-south-1.rds.amazonaws.com:5432/mydb


psql -h aprilasgapp.cvik8accw2tk.ap-south-1.rds.amazonaws.com -d mydb  -U postgres


export DB_LINK=postgresql://postgres:Admin1234@aprilasgapp.cvik8accw2tk.ap-south-1.rds.amazonaws.com:5432/mydb
pg_restore -d $DB_LINK -F c -j 4 -v mydb_20260419_092627.dump