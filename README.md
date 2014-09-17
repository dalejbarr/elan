R functions for pulling in data from .eaf files created with [ELAN](https://tla.mpi.nl/tools/tla-tools/elan), a tool for annotating media files.

```R
library(devtools)
install_github("dalebarr/elan")
```

Best experienced with [dplyr](https://github.com/hadley/dplyr).

Warning: Much beta.

## Some examples

### Reading in the tiers and annotations

```R
  # TODO: you need to have devtools
  #       and the elan package from github
  # so uncomment the two lines below to get started
  # install.packages("devtools")
  # install_github("dalejbarr/elan")

  library(elan)

  # parse the xml tree
  doc <- elanTree("DJI240211AC2.eaf") # name of your .eaf file goes here

  # list of all the tiers and their attributes
  tiers <- readTierList(doc)

  # read in "alignable" annotations
  # (associated with time codes)
  ann.ali <- readAnnotations(doc) # "alignable" annotations

  # read in "reference" annotations
  # (NOT associated with time codes)
  ann.ref <- readAnnotations(doc, "REF") 
```

### Examples of using ELAN tables in analyses

```R 
  # which of the tiers have time codes associated with them?
  tiers %>%
      inner_join(ann.ali, by="TIER_ID") %>% # join tiers to ann.ali
      select(TIER_ID) %>% # only keep the TIER_ID column
      unique # get rid of duplicates
```

```
| TIER_ID            |
|--------------------|
| A_phrase-segnum-en |
| B_phrase-segnum-en |
| C_phrase-segnum-en |
| D_phrase-segnum-en |
```

```R 
  # ... and how many annotations are there for each?
  tiers %>%
      inner_join(ann.ali, by="TIER_ID") %>%
      group_by(TIER_ID) %>%  # form groups based on TIER_ID
      summarize(n=n()) # count how many in each group
```

```
:  Source: local data frame [4 x 2]
: 
:              TIER_ID   n
: 1 A_phrase-segnum-en   1
: 2 B_phrase-segnum-en 112
: 3 C_phrase-segnum-en  53
: 4 D_phrase-segnum-en   4
```

```R 
  # who spent the most time speaking?
  tiers %>%
      filter(!is.na(PARTICIPANT)) %>% # PARTICIPANT field cannot be NA
      inner_join(ann.ali, by="TIER_ID") %>% 
      mutate(Duration=t1-t0) %>%  # calculate duration of each annotation
      group_by(PARTICIPANT) %>%
      summarize(nPhrases=n(), # count phrases
                secs=sum(Duration)/1000) # sum Duration & convert to secs
```

```
:  Source: local data frame [3 x 3]
: 
:   PARTICIPANT nPhrases   secs
: 1          AC        4  12.83
: 2         AJB      112 253.78
: 3          LM       53 110.16
```

```R 
  # and what was the speaking rate?
  # 1. calculate duration of each annotated segment
  segdur <- tiers %>%
      filter(!is.na(PARTICIPANT)) %>%
      inner_join(ann.ali, by="TIER_ID") %>%
      mutate(Duration=(t1-t0)/1000) %>%
      select(ANNOTATION_ID, PARTICIPANT, Duration)

  # 2. pull out the words, then link to segdur
  words <- ann.ref %>%
      # use a regular expression to select the TIER_ID we want
      filter(grepl("^[A-Z]_word.+fonipa-x-bai$", TIER_ID)) %>% 
      select(-ANNOTATION_ID, # drop it
             ANNOTATION_ID=ANNOTATION_REF, # replace for join
             Word=VALUE) # just rename the annotation field

  # now calculate speech rate
  words %>%
      group_by(ANNOTATION_ID) %>% # each ANNOTATION_ID is one turn
      summarize(nWords=n()) %>% # count words
      inner_join(segdur, by="ANNOTATION_ID") %>% # join with durations
      select(-ANNOTATION_ID) %>% # get rid of this field
      mutate(wps=nWords/Duration) %>% # rate=words/duration
      group_by(PARTICIPANT) %>% 
      summarize(meanWPS=mean(wps)) %>%
      arrange(desc(meanWPS)) # descending order (fastest spkr first)
```

```
:  Source: local data frame [3 x 2]
: 
:   PARTICIPANT  meanWPS
: 1          LM 2.051454
: 2          AC 1.902366
: 3         AJB 1.685535
```

```R
  # what words were used, and with what frequency?
  words %>%
      filter(!(Word %in% c(",", "?", "’", "…"))) %>% # lose code symbols
      group_by(Word) %>%
      summarize(n=n()) %>%
      filter(n>1) %>% # git rid of words that only occurred once
      arrange(desc(n)) # print in descending order
```

```
 Source: local data frame [99 x 2]

           Word  n
1          aŋgu 21
2         jaluf 20
3             a 14
4            ha 12
5            fi 10
6            ka 10
7            an  9
8        imereŋ  9
9           wol  9
10           ne  7
11        umooŋ  7
12         bare  6
13         buja  6
14         gëgu  6
15          Aao  5
16          aao  5
17           ah  5
18        amuki  5
19       biŋeen  5
20        butos  5
21     gumukuna  5
22       andëët  4
23          aŋg  4
24        bihan  4
25     gëtijini  4
26          hum  4
27        kunno  4
28        udëëk  4
29         ujal  4
30          umu  4
31      umónduk  4
32    ñoreendek  4
33    adóóriino  3
34        atiji  3
35     bumukuna  3
36        buruk  3
37         gúúb  3
38        iŋkan  3
39       jëñëër  3
40       kantik  3
41         kati  3
42      koluxun  3
43          kun  3
44            n  3
45           ni  3
46          num  3
47         tiaŋ  3
48       uñoŋot  3
49           Ah  2
50        adëëk  2
51       ajaxax  2
52      ajuŋëma  2
53     andëëgët  2
54       andëëk  2
55          ani  2
56        aseor  2
57     atijihum  2
58       añoŋot  2
59         aŋga  2
60        baxan  2
61        bimbi  2
62     binégkum  2
63 budiinkanaan  2
64        bugur  2
65      bumbooŋ  2
66          bun  2
67       damoox  2
68       duyaax  2
69          fan  2
70      gafutox  2
71     gajaxuux  2
72      gaxaana  2
73        hafaa  2
74        igini  2
75        inaak  2
76         ipux  2
77       iŋgune  2
78        jicum  2
79        jëmër  2
80          kon  2
81          kum  2
82          mes  2
83         nini  2
84       nuunom  2
85          tum  2
86       udégem  2
87      udëëgët  2
88     uhupunot  2
89       uliina  2
90       ulóbot  2
91   unëëreeneŋ  2
92     urukorox  2
93        utëëd  2
94           xa  2
95            ë  2
96          ëgu  2
97       ñonaak  2
98       ñoxaat  2
99     ñënjébun  2
```
