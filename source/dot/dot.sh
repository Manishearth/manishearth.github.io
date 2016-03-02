#!/bin/bash

for i in *.dot; do
    dot $i -Tpng -Gdpi=110 >../images/dotgen/$i.png
done