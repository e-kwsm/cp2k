!--------------------------------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations                              !
!   Copyright 2000-2024 CP2K developers group <https://cp2k.org>                                   !
!                                                                                                  !
!   SPDX-License-Identifier: GPL-2.0-or-later                                                      !
!--------------------------------------------------------------------------------------------------!

! **************************************************************************************************
!> \brief Provides interfaces to LAPACK eigenvalue/SVD routines
!> \note
!>      We are using LAPACK interfaces, so please make sure in IBM/AIX you have
!>      the lapack library before essl: "xlf90 ... -llapack -lessl" !!!
!> \par History
!>      JGH (26-5-2001): delay D/S C/Z problem to the lapack library call
!> \author APSI
! **************************************************************************************************
MODULE eigenvalueproblems

   USE kinds,                           ONLY: dp
   USE lapack,                          ONLY: lapack_cgesvd,&
                                              lapack_chpev,&
                                              lapack_sgesvd,&
                                              lapack_ssyev
#include "../base/base_uses.f90"

   IMPLICIT NONE

   PRIVATE

   PUBLIC :: diagonalise

   CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'eigenvalueproblems'

   INTERFACE diagonalise
      MODULE PROCEDURE diagonalise_ssyev
      MODULE PROCEDURE diagonalise_chpev
   END INTERFACE

   INTERFACE singular_values
      MODULE PROCEDURE cp2k_sgesvd
      MODULE PROCEDURE cp2k_cgesvd
   END INTERFACE

CONTAINS

! **************************************************************************************************
!> \brief ...
!> \param matrix ...
!> \param mysize ...
!> \param storageform ...
!> \param eigenvalues ...
!> \param eigenvectors ...
! **************************************************************************************************
   SUBROUTINE diagonalise_ssyev(matrix, mysize, storageform, eigenvalues, &
                                eigenvectors)

      REAL(KIND=dp), INTENT(IN)                          :: matrix(:, :)
      INTEGER, INTENT(IN)                                :: mysize
      CHARACTER(LEN=*), INTENT(IN)                       :: storageform
      REAL(KIND=dp), INTENT(OUT)                         :: eigenvalues(:), eigenvectors(:, :)

      CHARACTER, PARAMETER                               :: jobz = "V"

      CHARACTER                                          :: uplo
      INTEGER                                            :: info, lda, lwork
      REAL(KIND=dp)                                      :: work(3*mysize - 1)

      IF (storageform(1:5) == "Lower" .OR. &
          storageform(1:5) == "LOWER" .OR. &
          storageform(1:5) == "lower") THEN
         uplo = "L"
      ELSE IF (storageform(1:5) == "Upper" .OR. &
               storageform(1:5) == "upper" .OR. &
               storageform(1:5) == "UPPER") THEN
         uplo = "U"
      ELSE
         CPABORT("Unknown form of storage")
      END IF

      lda = SIZE(matrix, 1)
      lwork = 3*mysize - 1

      eigenvectors = matrix

      CALL lapack_ssyev(jobz, uplo, mysize, eigenvectors, lda, eigenvalues, &
                        work, lwork, info)
      IF (info /= 0) THEN
         CPABORT("Error in diagonalisation")
      END IF

   END SUBROUTINE diagonalise_ssyev

! **************************************************************************************************
!> \brief ...
!> \param matrix ...
!> \param mysize ...
!> \param storageform ...
!> \param eigenvalues ...
!> \param eigenvectors ...
! **************************************************************************************************
   SUBROUTINE diagonalise_chpev(matrix, mysize, storageform, eigenvalues, &
                                eigenvectors)

      COMPLEX(KIND=dp), INTENT(INOUT)                    :: matrix(:)
      INTEGER, INTENT(IN)                                :: mysize
      CHARACTER(LEN=*), INTENT(IN)                       :: storageform
      REAL(KIND=dp), INTENT(OUT)                         :: eigenvalues(:)
      COMPLEX(KIND=dp), INTENT(OUT)                      :: eigenvectors(:, :)

      CHARACTER, PARAMETER                               :: jobz = "V"

      CHARACTER                                          :: uplo
      INTEGER                                            :: info
      COMPLEX(KIND=dp)                                   :: work(2*mysize - 1)
      REAL(KIND=dp)                                      :: rwork(3*mysize - 2)

      IF (storageform(1:5) == "Lower" .OR. &
          storageform(1:5) == "LOWER" .OR. &
          storageform(1:5) == "lower") THEN
         uplo = "L"
      ELSE IF (storageform(1:5) == "Upper" .OR. &
               storageform(1:5) == "upper" .OR. &
               storageform(1:5) == "UPPER") THEN
         uplo = "U"
      ELSE
         CPABORT("Unknown form of storage")
      END IF

      CALL lapack_chpev(jobz, uplo, mysize, matrix, eigenvalues, &
                        eigenvectors, mysize, work, rwork, info)
      IF (info /= 0) THEN
         CPABORT("Error in diagonalisation")
      END IF

   END SUBROUTINE diagonalise_chpev

! **************************************************************************************************
!> \brief ...
!> \param matrix ...
!> \param svalues ...
!> \param mrow ...
!> \param ncol ...
!> \param uvec ...
!> \param vtvec ...
! **************************************************************************************************
   SUBROUTINE cp2k_sgesvd(matrix, svalues, mrow, ncol, uvec, vtvec)

      REAL(KIND=dp), INTENT(IN)                          :: matrix(:, :)
      REAL(KIND=dp), INTENT(OUT)                         :: svalues(:)
      INTEGER, INTENT(IN)                                :: mrow, ncol
      REAL(KIND=dp), INTENT(OUT)                         :: uvec(:, :), vtvec(:, :)

      CHARACTER, PARAMETER                               :: jobu = "A", jobvt = "A"

      INTEGER                                            :: info, lda, ldu, ldvt, lwork
      REAL(KIND=dp)                                      :: work(25*(mrow + ncol))

      lwork = 25*(mrow + ncol)
      lda = SIZE(matrix, 1)
      ldu = SIZE(uvec, 1)
      ldvt = SIZE(vtvec, 1)

      CALL lapack_sgesvd(jobu, jobvt, mrow, ncol, matrix, lda, svalues, &
                         uvec, ldu, vtvec, ldvt, work, lwork, info)
      IF (info /= 0) THEN
         CPABORT("Error in singular value decomposition.")
      END IF

   END SUBROUTINE cp2k_sgesvd

! **************************************************************************************************
!> \brief ...
!> \param matrix ...
!> \param svalues ...
!> \param mrow ...
!> \param ncol ...
!> \param uvec ...
!> \param vtvec ...
! **************************************************************************************************
   SUBROUTINE cp2k_cgesvd(matrix, svalues, mrow, ncol, uvec, vtvec)

      COMPLEX(KIND=dp), INTENT(IN)                       :: matrix(:, :)
      REAL(KIND=dp), INTENT(OUT)                         :: svalues(:)
      INTEGER, INTENT(IN)                                :: mrow, ncol
      COMPLEX(KIND=dp), INTENT(OUT)                      :: uvec(:, :), vtvec(:, :)

      CHARACTER, PARAMETER                               :: jobu = "A", jobvt = "A"

      INTEGER                                            :: info, lda, ldu, ldvt, lwork
      COMPLEX(KIND=dp)                                   :: work(25*(mrow + ncol))
      REAL(KIND=dp)                                      :: rwork(25*(mrow + ncol))

      lwork = 25*(mrow + ncol)
      lda = SIZE(matrix, 1)
      ldu = SIZE(uvec, 1)
      ldvt = SIZE(vtvec, 1)

      CALL lapack_cgesvd(jobu, jobvt, mrow, ncol, matrix, lda, svalues, &
                         uvec, ldu, vtvec, ldvt, work, lwork, rwork, info)
      IF (info /= 0) THEN
         CPABORT("Error in singular value decomposition.")
      END IF

   END SUBROUTINE cp2k_cgesvd

END MODULE eigenvalueproblems

