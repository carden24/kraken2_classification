# plotting tools for kraken classification results
# uses input matrices from the process_classification.R script
suppressMessages(library(RColorBrewer, quietly = TRUE, warn.conflicts = FALSE))
suppressMessages(library(ggpubr, quietly = TRUE, warn.conflicts = FALSE))

# testing color pal stuff
if(F){
    library(rafalib)
    mypar(3,2)
    pie(rep(1,8), col=brewer.pal(8,'Accent'), main='Accent')
    pie(rep(1,8), col=brewer.pal(8,'Dark2'), main='Dark2')
    pie(rep(1,12), col=brewer.pal(12,'Paired'), main='Paired')
    pie(rep(1,9), col=brewer.pal(9,'Set1'), main='Set1')
    pie(rep(1,8), col=brewer.pal(8,'Set2'), main='Set2')
    pie(rep(1,12), col=brewer.pal(12,'Set3'), main='Set3')

    mypar(1,1)
    n <- 12
    pie(rep(1,n), col=colorRampPalette(brewer.pal(12,'Paired'))(n))
    pie(rep(1,4), col=colorRampPalette(brewer.pal(12,'Paired')[11:12])(4))

    sapply(1:12, function(i) colorRampPalette(brewer.pal(12)[i,i+1])(3))

    # Getting all the R color brew pal options
    n <- 20
    qual_col_pals <- brewer.pal.info[brewer.pal.info$category == 'qual',]
    col_vector = unlist(mapply(brewer.pal, qual_col_pals$maxcolors, rownames(qual_col_pals)))
    pie(rep(1,n), col=col_vector[1:n])

    # old cols
    cols <- c(brewer.pal(12, 'Set3'), 'grey80')
    cols[9] = '#CD6155'

}

# plot many samples in a barplot horizontally
# samples must be in normalized fraction first
# include.unclassified: add unmpped reads into the mix barplot
# expects two rows in the matrix named 'Unclassified' and
#  'Classified at a higher level'
# plots them in shades of grey and changes y axis name
plot_many_samples <- function(kraken.mat, n.colors=12, tax.level.name = 'Species', include.unclassified =T){
    if (any(kraken.mat > 100)){
        stop('Must give normalized percent matrix')
    }
    # proceed with classified reads here
    unclassified.rownames <- c('Classified at a higher level', 'Unclassified')
    # renorm percentages
    kraken.mat.classified <- as.matrix(kraken.mat[!(rownames(kraken.mat) %in% unclassified.rownames),, drop=FALSE])
    kraken.mat.classified <- apply(kraken.mat.classified, 2, function(x) x/sum(x) * 100)
    # print(kraken.mat.classified)
    # ncolors must be equal or less to nrow kraken.mat
    n.colors <- min(n.colors, nrow(kraken.mat.classified))

    nmax <- 12
    cols <- colorRampPalette(brewer.pal(12,'Paired'))(nmax)[1:n.colors]
    # replace 11th color
    cols[11] <-  colorRampPalette(brewer.pal(12,'Paired')[11:12])(4)[2]
    # limit to ncolors
    cols <- cols[1:(n.colors)]

    # filter rows to most abundant taxa
    keep.rows <- names(sort(rowSums(kraken.mat.classified), decreasing = T))[1:n.colors]

    # add unclassified taxa if desired
    if (include.unclassified){
        if (!(all(unclassified.rownames %in% rownames(kraken.mat)))){
            stop('Must have unclassified rows in matrix')
        }
        kraken.mat.plot <- as.matrix(kraken.mat[c(keep.rows, unclassified.rownames),,drop=FALSE])
        kraken.mat.plot <- rbind(kraken.mat.plot, 100 - colSums(kraken.mat.plot))
        rownames(kraken.mat.plot)[nrow(kraken.mat.plot)] <- 'Other classified at this level'
        # reorder last rows
        kraken.mat.plot <- kraken.mat.plot[c(keep.rows, 'Other classified at this level', unclassified.rownames),,drop=FALSE]
        cols <- c(cols, 'grey50', 'grey60', 'grey80')
        use.ylab <- 'Percent of reads'
    } else{
        kraken.mat.plot <- kraken.mat.classified[keep.rows,,drop=FALSE]
        kraken.mat.plot <- rbind(kraken.mat.plot, 100 - colSums(kraken.mat.plot))
        rownames(kraken.mat.plot)[nrow(kraken.mat.plot)] <- 'Other classified at this level'
        use.ylab <- 'Percent of reads classified at this level'
        cols <- c(cols, 'grey50')
    }

    # melt to df and plot
    if (ncol(kraken.mat.plot) ==1 ){
        toplot.df <- data.frame(taxa=rownames(kraken.mat.plot),
                                sample=colnames(kraken.mat.plot),
                                value=kraken.mat.plot[,1])
    } else{
        toplot.df <- melt(kraken.mat.plot, varnames = c('taxa', 'sample'))
    }
    taxplot <- ggplot(data=toplot.df, aes(x = sample, y = value, fill = taxa)) +
        geom_bar(stat = 'identity') +
        scale_fill_manual(values = cols, name = tax.level.name) +
        # theme_bw() +
        # theme(panel.border = element_rect(), axis.text.x = element_text(angle = 90, hjust = 1)) +
        theme(axis.text.x = element_text(angle = 90, hjust = 1)) +
              # plot.margin = unit(c(0,0,0,0),'lines')) +
        labs(x='Sample', y=use.ylab)
        # guides(fill=FALSE)
    # taxplot
    return(taxplot)
}


plot_rarefaction_curve = function(class_counts, pdf_location, pdf_width = 8, pdf_height=8, tax.level.name = 'Species', steps = 30){
    class = as.matrix(class_counts[[tax.level.name]], drop = FALSE) #extract classifications of the desired taxonomic level
    class = class[rownames(class) != 'Unclassified',,drop=FALSE] #remove unclassified
    stepsize = max(apply(class, 2, sum)/steps) #calculate read count increase per subsample size step

    #shut the hell up
    options(warn=-1)

    pdf(pdf_location, pdf_width, pdf_height)
    rarecurve(t(class), step = stepsize)
    dev.off()

    options(warn=0)
}

plot_many_samples_with_diversity <- function(kraken.mat, diversity.df, y.title='Shannon Diversity', ...){
    stop('Depricated')
    if (ncol(diversity.df) != 2){
        stop('Must be two column dataframe: sample names in 1, diversity in 2')
    }
    taxplot <- plot_many_samples(kraken.mat, ...)
    diversity.df[,1] <- factor(diversity.df[,1], levels=diversity.df[,1])
    divplot <- ggplot(diversity.df, aes(x=sample, group=1, y=shannon)) +
        geom_point(stat='summary', fun.y=sum, size=5) +
        stat_summary(fun.y=sum, geom="line") +
        # theme_bw() +
        theme(axis.title.x=element_blank(),
              axis.text.x=element_blank(),
              axis.ticks.x=element_blank()) +
              # plot.margin = unit(c(0,0,0,0),'lines')) +
        ylim(0, max(diversity.df$shannon)*1.20) +
        labs(y=y.title)
    # divplot

    figure <- ggarrange(divplot, taxplot,ncol=1, align = 'v', nrow=2, heights = c(1,4),legend = 'right', common.legend = T)
    return(figure)

}

# figure <- plot_many_samples_with_diversity(bracken.species.fraction, diversity.df)
# annotate_figure(figure, top = text_grob('TEST', size=14))
# figure
#
# taxplot <- plot_many_samples(bracken.species.fraction, tax.level.name = 'Species') #+ labs(title = 'TEST')
# diversity.df <- data.frame(sample=names(div.list.species$shannon), shannon=div.list.species$shannon)


plot_many_samples_with_diversity_barplot <- function(kraken.mat, diversity.df, y.title='Shannon Diversity', plot.title='', ...){
    if (ncol(diversity.df) != 2){
        stop('Must be two column dataframe: sample names in 1, diversity in 2')
    }
    colnames(diversity.df) <- c('sample', 'shannon')
    taxplot <- plot_many_samples(kraken.mat, ...)
    diversity.df[,1] <- factor(diversity.df[,1], levels=diversity.df[,1])
    divplot <- ggplot(diversity.df, aes(x=sample, group=1, y=shannon)) +
        # as a bar plot instead?
        geom_bar(stat='identity', width = 0.5) +
        # theme_bw() +
        theme(axis.title.x=element_blank(),
              axis.text.x=element_blank(),
              axis.ticks.x=element_blank()) +
              # plot.margin = unit(c(0,0,0,0),'lines')) +
        ylim(0, max(diversity.df$shannon)*1.20) +
        labs(y=y.title)

    # print(taxplot)
    # print(divplot)

    figure <- ggarrange(divplot, taxplot,ncol=1, align = 'v', nrow=2, heights = c(1,4),legend = 'right', common.legend = T)
    if (plot.title!=''){
        figure <- annotate_figure(figure, top = text_grob(plot.title, size=14), fig.lab.pos='top.left')
        # figure <- annotate_figure(figure, fig.lab=plot.title, fig.lab.pos='top.left')
    }
    return(figure)

}
