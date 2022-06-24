
The git repos in cyber-dojo-start-points org dir can be cloned as follows:

```bash
gh repo list cyber-dojo-start-points -L 200 | cut -f1 | sort > gh-repo-names.txt 
while read in; do git clone https://github.com/$in; done < gh-repo-names.txt
```

