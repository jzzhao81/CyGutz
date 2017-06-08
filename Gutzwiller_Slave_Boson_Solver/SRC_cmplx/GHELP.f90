!******************************************************************************
! Copyright c 2013, The Ames Laboratory, Iowa State University, and Rutgers
! University*.  All rights reserved.
!
! This software was authored by Yongxin Yao, Nicola Lanata*, Gabriel Kotliar*,
! Cai-Zhuang Wang, and Kai-Ming Ho, at The Ames Laboratory and
! Rutgers University and was supported by the U.S.
! Department of Energy (DOE), Office of Science,
! Basic Energy Sciences, Materials Science and Engineering Division.
! The Ames Laboratory is operated by Iowa State University for DOE
! under U.S. Government contract DE-AC02-07CH11358.
! The U.S. Government has the rights to use, reproduce, and
! distribute this software.
! NEITHER THE GOVERNMENT, THE AMES LABORATORY, IOWA STATE UNIVERSITY,
! NOR RUTGERS UNIVERSITY MAKES ANY WARRANTY,
! EXPRESS OR IMPLIED, OR ASSUMES ANY LIABILITY FOR THE USE OF THIS SOFTWARE.
! If software is modified to produce derivative works,
! such modified software should be clearly marked,
! so as to not confuse it with the version available from
! The Ames Laboratory and Rutgers University.
!
! Additionally, redistribution and use in source and binary forms,
! with or without modification,
! are permitted provided that the following conditions are met:
!
!     Redistribution of source code must retain the above copyright notice,
!     this list of conditions, and the following disclaimer.
!
!     Redistribution in binary form must reproduce the above copyright notice,
!     this list of conditions, and the following disclaimer
!     in the documentation and/or other materials provided with distribution.
!
!     Neither the name of The Ames Laboratory, Iowa State University,
!     Rutgers University, the U.S. Government, nor the names of
!     its contributors may be used to endorse or promote products derived
!     from this software without specific prior written permission.
!
! THIS SOFTWARE IS PROVIDED BY THE AMES LABORATORY, IOWA STATE UNIVERSITY,
! RUTGERS UNIVERSITY, AND CONTRIBUTORS "AS IS"
! AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
! THE IMPLIED WARRANTIES OF MERCHANTABILITY
! AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
! IN NO EVENT SHALL THE GOVERNMENT, THE AMES LABORATORY,
! IOWA STATE UNIVERSITY, RUTGERS UNIVERSITY, OR CONTRIBUTORS BE LIABLE
! FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
! EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
! PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
! LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
! HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
! WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
! OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
! EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
!******************************************************************************

subroutine set_gmpi()
    use gprec
    use omp_lib
    use gmpi
    use ghdf5_base
    use bandstru
#ifdef mpi_mode
    use mpi
#endif
    implicit none
      
    integer nk1,i,imap,isum
    integer local_imp(wh%num_imp)
    character*77 f_name
    logical lexist
      
    f_name='GOMP.h5'
    inquire(file=f_name,exist=lexist)
    if(lexist)then
        gp%ipar=1
    endif
#ifdef mpi_mode
    if(.not.lexist)then
        f_name=file_name(gp%myrank,'GMPI')
        inquire(file=f_name,exist=lexist)
        if(lexist)gp%ipar=2
    endif
#endif
    if(gp%ipar==0)then
        allocate(gp%kvec(gp%nvec,3))
        if(kpt%dim<0)then
            write(0,'(" error in set_gmpi: kpt%dim not set yet!")')
            stop
        endif
        nk1=nint(dble(kpt%dim)/gp%nprocs)
        gp%kvec(1,1)=gp%myrank
        gp%kvec(1,3)=nk1*gp%myrank
        gp%kvec(1,2)=min(nk1,kpt%dim-gp%kvec(1,3))
    else
        call gh5_open_r(f_name,f_id)
        call gh5_read(gp%nvec,'/nvec',f_id)
        allocate(gp%kvec(gp%nvec,3))
        call gh5_read(gp%kvec,gp%nvec,3,'/KVEC',f_id)
        call gh5_close(f_id)
        if(gp%ipar==1)then
            call omp_set_num_threads(gp%nprocs)
            write(gp%io,'(" omp_num_threads=",i2)')gp%nprocs
        else
            call omp_set_num_threads(1)
        endif
    endif

    call set_kpt_diml(sum(gp%kvec(:,2)))

    !< set local_imp
    local_imp=0
    isum=0
    do i=1,wh%num_imp
        imap=wh%imap_imp(i)
        if(imap==i)then
            if(gp%myrank==mod(isum,gp%nprocs).or.gp%ipar==1)then
                local_imp(i)=i
            endif
            isum=isum+1
        else
            if(local_imp(imap)>0)local_imp(i)=i
        endif
    enddo
    call wh_set_local_imp(local_imp)
    return
      
end subroutine set_gmpi


subroutine output_energies(io)
    use gprec
    use warehouse
    use dcstd
    use bandstru
    implicit none
    integer,intent(in)::io

    call output_energies_wh(io)
    call output_energies_dc(io)
    write(io,'(" total band energy = ",f0.7)')bnd%eband
    return

end subroutine output_energies


subroutine gh5_wrt_kswt()
    use gprec
    use warehouse
    use dcstd
    use bandstru
    use ghdf5_base
    use gmpi
    implicit none

    real(8) vnorm1,e_gamma_dc
    integer ivec,ikp,ikpl,iks,nkp,nbands
    integer nemin,nemax
    complex(8),pointer :: p_kswt(:,:)
      
    vnorm1=1.d0
    if(wh%iso.eq.2.and.bnd%ispin_in.eq.1)vnorm1=.5d0
    e_gamma_dc=sum(wh%eu2)+sum(wh%et1)-wh%edcla1-sum(dc%e)

    ikpl=0
    do ivec=1,gp%nvec
        call gh5_open_w(file_name(gp%kvec(ivec,1),'KSWT'), f_id)
        call gh5_write(bnd%ef,'/e_fermi',f_id)
        call gh5_write(e_gamma_dc,'/e_gamma_dc',f_id)
        call gh5_write(bnd%eband,'/e_band',f_id)
        do iks=1,gp%kvec(ivec,2)
            ikp=gp%kvec(ivec,3)+iks
                if(gp%ipar==1)then
                    ikpl=ikp
                else
                    ikpl=ikpl+1
                endif
            nbands=bnd%ne(3,ikp)-bnd%ne(2,ikp)+1
            p_kswt(1:nbands,1:nbands)=>bnd%hk0(1:nbands**2,sym%ie,ikpl)
            p_kswt=p_kswt/vnorm1 ! to be consistent with dmft2
            call gh5_create_group('/IKP_'//trim(int_to_str(ikp)), f_id)
            call gh5_write(bnd%ne(2,ikp), &
                        &'/IKP_'//trim(int_to_str(ikp))//'/nemin',f_id)
            call gh5_write(bnd%ne(3,ikp), &
                        &'/IKP_'//trim(int_to_str(ikp))//'/nemax',f_id)
            call gh5_write(p_kswt,nbands,nbands, &
                    &'/IKP_'//trim(int_to_str(ikp))//'/KSWT',f_id)
        enddo
        call gh5_close(f_id)
    enddo
    nullify(p_kswt)
    return
      
end subroutine gh5_wrt_kswt
