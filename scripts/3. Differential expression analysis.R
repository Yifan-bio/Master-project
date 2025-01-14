# This script is put together to allow the running of differential expression analysis using RNA-seq
# Last modification: 14 March 2023

# Package version
#
#
#
#

#### Preparation of tximport dataframes ####

# Result from salmon are recorded as transcript counts, but we need to convert 
# these into gene counts, to do this, there needs to be a conversion table to 
# allow the algorithm know the gene each transcript originate from.
# This section preps this reference table by using the corresponding gtf file 
# (metadate file) that was used for salmon index creation. 

library(GenomicFeatures)

# function to create the tx2gene file
tx2gene_creation = function(gtf_file) {
  # Intaking the gtf file as binary object for R
  temp1 = GenomicFeatures::makeTxDbFromGFF(file = gtf_file)
  # Extracting the required information
  temp2 = AnnotationDbi::keys(x = temp1,
                              keytype = 'TXNAME')
  # Selecting the required information
  temp = AnnotationDbi::select(temp1,
                               keys = temp2,
                               columns = 'GENEID',
                               keytype = 'TXNAME')
  return(temp)
}

# Running the function to create the refence table.
tx2gene = tx2gene_creation('../support_doc/Gencode/gencode.v40.annotation.gtf')


#### Importing Result from salmon using tximport #### 

library("tximport")

# Listing the location of the salmon output file
files = c('./Input/0hr_rep1/quant.sf',
          './Input/0hr_rep2/quant.sf',
          './Input/24hr_rep1/quant.sf',
          './Input/24hr_rep2/quant.sf')

# Import files into tximport and converting transcript counts to gene counts
txi.salmon <- tximport(files = files,
                       type = "salmon",
                       txOut = FALSE,
                       tx2gene = tx2gene,
                       ignoreAfterBar = T)

# Creating a table with the metainfo
sampleTable <- data.frame(condition = factor(rep(c("control", "treated"),each = 2)))

# Combining the metainfo with the tximport results
rownames(sampleTable) <- colnames(txi.salmon$counts) 

# remove(files,tx2gene)


#### Running DESeq2 #####

library("DESeq2")

# Importing result from tximport into DESeq2 to allow the correct format for
# differential analysis
dds <- DESeqDataSetFromTximport(txi = txi.salmon, 
                                colData = sampleTable,
                                design = ~ condition)

# The pre-deseq2 filering step (Temp removed)
# keep <- rowMeans(counts(dds)) > 20 & rowSums(counts(dds) == 0) != 3 |
#        rowSums(counts(dds)[,1:2]) < 1 &  rowSums(counts(dds)) > 25 |
#        rowSums(counts(dds)[,3:4]) < 1 &  rowSums(counts(dds)) > 25  
# dds <- dds[keep,]

# Running the differential expression analysis 
dds <- DESeq(object = dds,
             test = 'Wald')

# Getting the results out of DEseq2 and shrinking the L2FC of some lowly expressed genes
result = lfcShrink(dds = dds,
                   coef = "condition_treated_vs_control",
                   type = "apeglm"
                   )

#### Adding annotation to DESeq2 results #####

gene_annot <- function(result = result,dds = dds,gtf_file) {
  
  # Creating a ID to symbol conversion table
  gtf_file <- rtracklayer::import(gtf_file)
  gtf_file <- as.data.frame(gtf_file)
  gtf_file <- unique(gtf_file[,c("gene_id","gene_name")])
  
  # Putting all important information into a single object
  res <- merge(as.data.frame(result),
               as.data.frame(counts(dds,normalized=TRUE)),
               by = "row.names",
               sort = FALSE)
  # Putting the gene symbol with the gene id
  res <- merge(x = res,
               y = gtf_file,
               by.x = "Row.names",
               by.y = "gene_id")
  
  # Getting gene stable version number
  res$Row.names <- gsub("(ENSG[0-9]+)\\.[0-9]+", "\\1",res$Row.names) 
 
  return(res)
}

resdata = gene_annot(result = result,dds = dds,gtf_file = "../support_doc/Gencode/gencode.v40.annotation.gtf.gz")

resdata = resdata[resdata$baseMean > 20,]

sig = resdata[resdata$padj < 0.05 & abs(resdata$log2FoldChange) > 2,]


#### Over-enrichment Analysis for GO terms ####

library("clusterProfiler")
library("org.Hs.eg.db")

ORA_GO = function(background,sig_gene,term = 'ALL') {
  # Setting the universal genes
  BG = as.character(background$Row.names)
  # Creating the genelist for ORA
  genelist = sig_gene$log2FoldChange
  names(genelist) = sig_gene$Row.names
  genelist = sort(genelist,decreasing = TRUE)
  gene = names(genelist)[abs(genelist) > 2]
  # Enrichment analysis using clusterProfiler
  res <- enrichGO(gene = gene, 
                  universe = BG,
                  OrgDb = 'org.Hs.eg.db',
                  ont = term,
                  keyType = 'ENSEMBL',
                  pAdjustMethod = "BH",
                  pvalueCutoff = 0.01,
                  readable = TRUE)
  return(res)
}

ORA = ORA_GO(background = resdata,sig_gene = sig,term = "ALL")
